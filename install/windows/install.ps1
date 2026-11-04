param([string]$BashPath)

$projtoolDirectory = Split-Path (Split-Path $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stateDirectory = Join-Path $env:USERPROFILE '.config\projtool'
if ($env:XDG_CONFIG_HOME) { $stateDirectory = Join-Path $env:XDG_CONFIG_HOME 'projtool' }
$binDirectory = Join-Path $env:LOCALAPPDATA 'Programs\ProjTool\bin'
$stateFile = Join-Path $stateDirectory 'install.json'
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('projtool-install-' + [guid]::NewGuid())
$previousPaths = @()
if (Test-Path $stateFile) { $previousPaths = @((Get-Content $stateFile -Raw | ConvertFrom-Json).addedPaths) }
$releaseCache = @{}
$addedPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($entry in $previousPaths) { $addedPaths.Add($entry) }

function Add-ProcessPath([string]$Directory) {
    if ($Directory -and (Test-Path $Directory)) {
        $env:Path = $Directory + ';' + (($env:Path -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $Directory.TrimEnd('\') }) -join ';')
    }
}

function Find-Application([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
}

function Get-GitHubRelease([string]$Repository) {
    if (-not $script:releaseCache.ContainsKey($Repository)) {
        $script:releaseCache[$Repository] = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ 'User-Agent' = 'ProjTool-installer' }
    }
    return $script:releaseCache[$Repository]
}

function Get-ReleaseAsset([string]$Repository, [string]$Pattern) {
    $release = Get-GitHubRelease $Repository
    $assets = @($release.assets | Where-Object { $_.name -match $Pattern })
    if ($assets.Count -ne 1) { throw "Cannot identify the $Repository installer for this computer." }
    $asset = $assets[0]
    $destination = Join-Path $temporaryDirectory $asset.name
    Write-Host "Downloading $($asset.name)..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $destination -UseBasicParsing
    if ($asset.digest -match '^sha256:(.+)$') {
        if ((Get-FileHash $destination -Algorithm SHA256).Hash -ine $Matches[1]) { throw "Checksum mismatch: $($asset.name)" }
    }
    return $destination
}

function Get-LatestPythonVersion {
    $index = (Invoke-WebRequest 'https://www.python.org/ftp/python/' -UseBasicParsing).Content
    $versions = [regex]::Matches($index, 'href="(3\.\d+\.\d+)/"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending -Unique
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
    foreach ($version in $versions) {
        try {
            $response = Invoke-WebRequest "https://www.python.org/ftp/python/$version/python-$version-$architecture.exe" -Method Head -UseBasicParsing
            if ($response.StatusCode -eq 200) { return $version }
        } catch {
            if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
        }
    }
    throw 'Could not find a stable Python installer.'
}

function Find-Python([string]$Version) {
    $candidates = @()
    foreach ($name in @('python.exe', 'python3.exe')) {
        $candidates += @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    }
    $candidates += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe') -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -like '*\Microsoft\WindowsApps\*') { continue }
        try {
            $found = @(& $candidate -c 'import sys; print(sys.version.split()[0])' 2>$null) -join ''
            if ($LASTEXITCODE -eq 0 -and $found -eq $Version) {
                $base = @(& $candidate -c 'import sys; print(sys.base_prefix)' 2>$null) -join ''
                $executable = Join-Path $base 'python.exe'
                if ($LASTEXITCODE -eq 0 -and (Test-Path $executable)) { return $executable }
            }
        } catch {}
    }
}

function Install-Python([string]$Version) {
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $installer = Join-Path $temporaryDirectory 'python-installer.exe'
    Write-Host "Installing Python $Version..."
    Invoke-WebRequest "https://www.python.org/ftp/python/$Version/python-$Version-$architecture.exe" -OutFile $installer -UseBasicParsing
    if ((Get-AuthenticodeSignature $installer).Status -ne 'Valid') { throw 'Python installer signature verification failed.' }
    $parsed = [version]$Version
    $directory = Join-Path $env:LOCALAPPDATA ('Programs\Python\Python' + $parsed.Major + $parsed.Minor)
    $process = Start-Process $installer -Wait -PassThru -ArgumentList @('/quiet', 'InstallAllUsers=0', 'Include_launcher=1', 'Include_test=0', 'PrependPath=1', ('TargetDir="' + $directory + '"'))
    if ($process.ExitCode -notin @(0, 3010)) { throw "Python installation failed ($($process.ExitCode))." }
    $executable = Join-Path $directory 'python.exe'
    if (-not (Test-Path $executable)) { throw 'Python installation did not produce python.exe.' }
    return $executable
}

function Get-LatestJuliaVersion {
    $releases = Invoke-RestMethod 'https://julialang-s3.julialang.org/bin/versions.json'
    $release = $releases.PSObject.Properties | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and $_.Value.stable } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $release) { throw 'Could not find a stable Julia release.' }
    return $release.Name
}

function Find-Julia([string]$Version) {
    $candidates = @(Get-Command julia.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($pattern in @('Programs\Julia\julia-*\bin\julia.exe', 'Programs\julia-*\bin\julia.exe')) {
        $candidates += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA $pattern) -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            $found = @(& $candidate --startup-file=no -e 'print(VERSION)' 2>$null) -join ''
            if ($LASTEXITCODE -eq 0 -and $found -eq $Version) {
                $directory = @(& $candidate --startup-file=no -e 'print(Sys.BINDIR)' 2>$null) -join ''
                if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $directory 'julia.exe'))) {
                    return (Join-Path $directory 'julia.exe')
                }
            }
        } catch {}
    }
}

function Install-Julia([string]$Version) {
    $releases = Invoke-RestMethod 'https://julialang-s3.julialang.org/bin/versions.json'
    $release = $releases.PSObject.Properties | Where-Object { $_.Name -eq $Version -and $_.Value.stable } | Select-Object -First 1
    if (-not $release) { throw "Julia $Version is not an available stable release." }
    $asset = $release.Value.files | Where-Object { $_.os -eq 'winnt' -and $_.arch -eq 'x86_64' -and $_.url.EndsWith('.zip') } | Select-Object -First 1
    if (-not $asset -or -not [Environment]::Is64BitOperatingSystem) { throw 'No supported Julia download found for this computer.' }
    $archive = Join-Path $temporaryDirectory 'julia.zip'
    Write-Host "Installing Julia $($release.Name)..."
    Invoke-WebRequest $asset.url -OutFile $archive -UseBasicParsing
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ine $asset.sha256) { throw 'Julia download checksum mismatch.' }
    $extracted = Join-Path $temporaryDirectory 'julia'
    New-Item $extracted -ItemType Directory -Force | Out-Null
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $archive -C $extracted
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the Julia archive.' }
    $executable = Get-ChildItem $extracted -Directory | ForEach-Object { Get-Item (Join-Path $_.FullName 'bin\julia.exe') -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $executable) { throw 'Julia archive does not contain julia.exe.' }
    $directory = Join-Path $env:LOCALAPPDATA ('Programs\Julia\julia-' + $release.Name)
    if (Test-Path $directory) { throw "Julia installation directory already exists: $directory" }
    New-Item (Split-Path $directory) -ItemType Directory -Force | Out-Null
    Move-Item $executable.Directory.Parent.FullName $directory
    return (Join-Path $directory 'bin\julia.exe')
}

function Get-MissingTexPackages {
    $kpsewhich = Join-Path $tinytexDirectory 'bin\windows\kpsewhich.exe'
    foreach ($line in Get-Content (Join-Path $projtoolDirectory 'source\tex-packages.txt')) {
        $package, $probe = $line.Split('|')
        if ($probe.StartsWith('@')) {
            if (-not (Test-Path (Join-Path $tinytexDirectory ('bin\windows\' + $probe.Substring(1) + '.exe')))) { $package }
        } elseif (-not (Test-Path $kpsewhich)) {
            $package
        } else {
            $found = & $kpsewhich $probe
            if ($LASTEXITCODE -ne 0 -or -not $found) { $package }
        }
    }
}

function Write-Launcher([string]$Path, [string]$Content) {
    if ((Test-Path $Path) -and -not ([IO.File]::ReadAllText($Path).Contains('PROJTOOL_LAUNCHER=1'))) {
        throw "Refusing to replace an unrelated launcher: $Path"
    }
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function ConvertTo-ShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "'\''") + "'"
}

New-Item $temporaryDirectory -ItemType Directory -Force | Out-Null
try {
    foreach ($entry in (([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')) -split ';')) {
        if ($entry -and ($env:Path -split ';') -inotcontains $entry) { $env:Path += ';' + $entry }
    }
    $gitRoots = @((Join-Path $env:LOCALAPPDATA 'Programs\Git'), (Join-Path $env:ProgramFiles 'Git'))
    $git = Find-Application 'git.exe'
    if ($git) { $gitRoots = @((Split-Path (Split-Path $git))) + $gitRoots }
    foreach ($root in $gitRoots) {
        if (-not $BashPath -and (Test-Path "$root\bin\bash.exe") -and (Test-Path "$root\cmd\git.exe")) {
            $BashPath = "$root\bin\bash.exe"
            Add-ProcessPath "$root\cmd"
        }
    }
    $gitRelease = Get-GitHubRelease 'git-for-windows/git'
    $latestGit = $gitRelease.tag_name.TrimStart('v')
    $currentGit = if ($git) { (@(& $git --version) -join '').Replace('git version ', '').Trim() } else { '' }
    if (-not $BashPath -or -not (Test-Path $BashPath) -or $currentGit -ne $latestGit) {
        $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { '64-bit' }
        $installer = Get-ReleaseAsset 'git-for-windows/git' "^Git-[0-9.]+-$architecture\.exe$"
        $gitRoot = if ($BashPath) { Split-Path (Split-Path $BashPath) } else { Join-Path $env:LOCALAPPDATA 'Programs\Git' }
        $allUsers = $gitRoot.StartsWith($env:ProgramFiles, [StringComparison]::OrdinalIgnoreCase)
        $scope = if ($allUsers) { '/ALLUSERS' } else { '/CURRENTUSER' }
        $options = @{ FilePath=$installer; Wait=$true; PassThru=$true; ArgumentList=@($scope, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/DIR="' + $gitRoot + '"'), '/o:PathOption=Cmd') }
        if ($allUsers) { $options.Verb='RunAs' }
        $process = Start-Process @options
        if ($process.ExitCode -ne 0) { throw "Git installation failed ($($process.ExitCode))." }
        $BashPath = Join-Path $gitRoot 'bin\bash.exe'
        Add-ProcessPath (Join-Path $gitRoot 'cmd')
    }
    $git = Find-Application 'git.exe'
    & $git --version
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $BashPath)) { throw 'Git/Bash installation could not be verified.' }
    $gitRoot = Split-Path (Split-Path $BashPath)
    $cygpath = Join-Path $gitRoot 'usr\bin\cygpath.exe'

    $pandocRelease = Get-GitHubRelease 'jgm/pandoc'
    $pandocDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Pandoc'
    Add-ProcessPath $pandocDirectory
    $pandoc = Find-Application 'pandoc.exe'
    $pandocVersion = if ($pandoc) { @(& $pandoc --version)[0] -replace '^pandoc(?:\.exe)?\s+', '' } else { '' }
    if ($pandocVersion -ne $pandocRelease.tag_name.TrimStart('v')) {
        $archive = Get-ReleaseAsset 'jgm/pandoc' '^pandoc-[0-9.]+-windows-x86_64\.zip$'
        $extracted = Join-Path $temporaryDirectory 'pandoc'
        Expand-Archive $archive $extracted
        $executable = Get-ChildItem $extracted -Filter pandoc.exe -Recurse | Select-Object -First 1
        if (-not $executable) { throw 'The Pandoc archive does not contain pandoc.exe.' }
        New-Item $pandocDirectory -ItemType Directory -Force | Out-Null
        Get-ChildItem $executable.Directory.FullName -Force | Copy-Item -Destination $pandocDirectory -Recurse -Force
        Add-ProcessPath $pandocDirectory
    }

    $texRelease = Get-GitHubRelease 'rstudio/tinytex-releases'
    $texYear = [regex]::Match($texRelease.tag_name, '\d{4}').Value
    $tinytexDirectory = Join-Path $env:APPDATA 'TinyTeX'
    $texExecutable = Join-Path $tinytexDirectory 'bin\windows\pdflatex.exe'
    $texVersion = if (Test-Path $texExecutable) { @(& $texExecutable --version) -join ' ' } else { '' }
    if ($texVersion -notmatch ('TeX Live ' + $texYear)) {
        if (Test-Path $tinytexDirectory) { $tinytexDirectory = Join-Path $env:APPDATA ('TinyTeX-' + $texYear) }
        $texExecutable = Join-Path $tinytexDirectory 'bin\windows\pdflatex.exe'
        if (-not (Test-Path $texExecutable)) {
            if (Test-Path $tinytexDirectory) { throw "Incomplete TinyTeX installation exists: $tinytexDirectory" }
            $archive = Get-ReleaseAsset 'rstudio/tinytex-releases' '^TinyTeX-v[0-9.]+\.zip$'
            $extracted = Join-Path $temporaryDirectory 'tinytex'
            New-Item $extracted -ItemType Directory | Out-Null
            & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $archive -C $extracted
            if ($LASTEXITCODE -ne 0) { throw 'TinyTeX extraction failed.' }
            $manager = Get-ChildItem $extracted -Filter tlmgr.bat -Recurse | Select-Object -First 1
            if (-not $manager) { throw 'The TinyTeX archive does not contain tlmgr.bat.' }
            Move-Item $manager.Directory.Parent.Parent.FullName $tinytexDirectory
        }
    }
    Add-ProcessPath (Join-Path $tinytexDirectory 'bin\windows')
    $texTemporary = (& $cygpath -d $temporaryDirectory).Trim()
    $removeTexTemporary = $false
    if ($texTemporary -match '\s') {
        $texTemporary = Join-Path $env:PUBLIC ('projtool-tex-' + [guid]::NewGuid())
        New-Item $texTemporary -ItemType Directory | Out-Null
        $removeTexTemporary = $true
    }
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    $previousTmpDir = $env:TMPDIR
    try {
        $env:TEMP = $texTemporary
        $env:TMP = $texTemporary
        $env:TMPDIR = $texTemporary
        $manager = Find-Application 'tlmgr.bat'
        & $manager option repository https://ctan.math.illinois.edu/systems/texlive/tlnet
        if ($LASTEXITCODE -ne 0) { throw 'Could not select the current TeX Live repository.' }
        & $manager update --self --all
        if ($LASTEXITCODE -ne 0) { throw 'Could not update TeX Live.' }
        $requiredPackages = @(Get-Content (Join-Path $projtoolDirectory 'source\tex-packages.txt') | ForEach-Object { $_.Split('|')[0] })
        & $manager install @requiredPackages
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the required LaTeX packages and their dependencies.' }
        if (@(Get-MissingTexPackages).Count -gt 0) { throw 'LaTeX package verification failed.' }
        & (Join-Path $tinytexDirectory 'bin\windows\fmtutil-sys.exe') --all
        if ($LASTEXITCODE -ne 0) { throw 'Could not regenerate the updated LaTeX formats.' }
    } finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        $env:TMPDIR = $previousTmpDir
        if ($removeTexTemporary) { Remove-Item $texTemporary -Recurse -Force }
    }
    $pythonVersion = Get-LatestPythonVersion
    $python = Find-Python $pythonVersion
    if (-not $python) { $python = Install-Python $pythonVersion }
    $requiredJuliaVersion = Get-LatestJuliaVersion
    $juliaup = Find-Application 'juliaup.exe'
    if ($juliaup) {
        & $juliaup add $requiredJuliaVersion
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the stable Julia release.' }
        & $juliaup default $requiredJuliaVersion
        if ($LASTEXITCODE -ne 0) { throw 'Could not set the default Julia version.' }
        $juliaLauncher = Join-Path (Split-Path $juliaup) 'julia.exe'
        $directory = @(& $juliaLauncher "+$requiredJuliaVersion" --startup-file=no -e 'print(Sys.BINDIR)') -join ''
        if ($LASTEXITCODE -ne 0) { throw 'Could not locate the stable Julia runtime.' }
        $julia = Join-Path $directory 'julia.exe'
    } else {
        $julia = Find-Julia $requiredJuliaVersion
        if (-not $julia) { $julia = Install-Julia $requiredJuliaVersion }
    }
    $verifiedJuliaVersion = @(& $julia --startup-file=no -e 'print(VERSION)') -join ''
    if ($LASTEXITCODE -ne 0 -or $verifiedJuliaVersion -ne $requiredJuliaVersion) { throw 'Julia version verification failed.' }
    Write-Host "Using Julia $requiredJuliaVersion."
    Add-ProcessPath (Split-Path $julia)
    $pythonEnvironment = Join-Path (Split-Path $binDirectory) 'python'
    & $python (Join-Path $projtoolDirectory 'source\install_python.py') $pythonEnvironment (Join-Path $projtoolDirectory 'source\python-requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not update the managed Python environment.' }
    $pythonBin = Join-Path $pythonEnvironment 'Scripts'
    $environmentPython = Join-Path $pythonBin 'python.exe'
    $juliaProjects = @('dissertation', 'note', 'preprint', 'presentation') | ForEach-Object { Join-Path $projtoolDirectory ('examples\' + $_ + '\code\julia') }
    & $julia --startup-file=no (Join-Path $projtoolDirectory 'source\prepare_julia.jl') @juliaProjects
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the Julia example packages.' }
    $dependencyDirectories = @($pythonBin, (Split-Path $python), (Split-Path $julia))
    foreach ($name in @('git.exe', 'pandoc.exe', 'pdflatex.exe', 'latexmk.exe', 'bibtexu.exe')) {
        $executable = Find-Application $name
        if (-not $executable) { throw "Required program is unavailable: $name" }
        $version = @(& $executable --version)
        if ($LASTEXITCODE -ne 0) { throw "Required program could not run: $name" }
        Write-Host $version[0]
        $dependencyDirectories += Split-Path $executable
    }
    $dependencyDirectories = @($dependencyDirectories | Select-Object -Unique)
    New-Item $binDirectory, $stateDirectory -ItemType Directory -Force | Out-Null
    $shellPath = (@($dependencyDirectories | ForEach-Object { & $cygpath -u $_ }) -join ':')
    $scriptPath = (& $cygpath -u (Join-Path $projtoolDirectory 'source\projtool.sh')).Trim()
    $launcher = "#!/usr/bin/env bash`nPROJTOOL_LAUNCHER=1`nexport PATH=" + (ConvertTo-ShellLiteral $shellPath) + ':"$PATH"' + "`nexport JUPYTER_PATH=" + (ConvertTo-ShellLiteral ((& $cygpath -m (Join-Path $pythonEnvironment 'share\jupyter')).Trim())) + "`nexec bash " + (ConvertTo-ShellLiteral $scriptPath) + ' "$@"' + "`n"
    Write-Launcher (Join-Path $binDirectory 'projtool') $launcher
    $nativeLauncher = (Join-Path $binDirectory 'projtool').Replace('\', '/')
    $batch = "@echo off`r`nsetlocal DisableDelayedExpansion`r`nset PROJTOOL_LAUNCHER=1`r`n" + '"' + $BashPath.Replace('%', '%%') + '" --noprofile --norc "' + $nativeLauncher.Replace('%', '%%') + '" %*' + "`r`nexit /b %errorlevel%`r`n"
    Write-Launcher (Join-Path $binDirectory 'projtool.cmd') $batch

    $legacyState = Join-Path $stateDirectory 'install'
    if (Test-Path $legacyState) {
        $legacy = @(Get-Content $legacyState)
        if ($legacy.Count -ge 2 -and $legacy[1].StartsWith('alias projtool=')) {
            $profile = (& $cygpath -w $legacy[0]).Trim()
            if (Test-Path $profile) {
                $content = [IO.File]::ReadAllText($profile)
                $content = [regex]::Replace($content, '(?m)^' + [regex]::Escape($legacy[1]) + '\r?\n?', '')
                [IO.File]::WriteAllText($profile, $content, $utf8)
            }
            Remove-Item $legacyState
        } else { throw 'Unrecognized previous ProjTool installation record.' }
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split ';' | Where-Object { $_ })
    $globalDirectories = @($pythonBin, (Split-Path $python), (Join-Path (Split-Path $python) 'Scripts'), (Split-Path $julia)) + @($dependencyDirectories | Where-Object { $_ -ne $pythonBin }) + @($pythonBin, $binDirectory)
    $globalDirectories = @($globalDirectories | Select-Object -Unique)
    foreach ($owned in @($pythonBin, $binDirectory)) {
        if ($userEntries -inotcontains $owned -and -not $addedPaths.Contains($owned)) { $addedPaths.Add($owned) }
    }
    $userEntries = $globalDirectories + @($userEntries | Where-Object { $globalDirectories -inotcontains $_ })
    $state = @{ binDirectory = $binDirectory; addedPaths = @($addedPaths.ToArray()); pythonEnvironment = $pythonEnvironment }
    [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), $utf8)
    [Environment]::SetEnvironmentVariable('Path', ($userEntries -join ';'), 'User')
    Add-ProcessPath $binDirectory
    Add-Type -Namespace ProjTool -Name EnvironmentNotification -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)] public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint flags, uint timeout, out System.IntPtr result);'
    $result = [IntPtr]::Zero
    [void][ProjTool.EnvironmentNotification]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [IntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    & (Join-Path $binDirectory 'projtool.cmd') --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The installed projtool launcher failed verification.' }
    Write-Host 'Installed projtool and its dependencies. Open a new terminal and fully restart VS Code.'
} finally {
    Remove-Item $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
