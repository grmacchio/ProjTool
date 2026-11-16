param([ValidateSet('all', 'python', 'julia')][string]$Component = 'all')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $env:USERPROFILE '.config' }
$Config = Join-Path $ConfigHome 'projtool'
$env:PYTHONDONTWRITEBYTECODE = '1'
Remove-Item Env:PYTHONHOME, Env:PYTHONPATH -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-StandardPython {
    $Candidates = @()
    foreach ($Registry in @('HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore', 'HKLM:\Software\WOW6432Node\Python\PythonCore')) {
        if (Test-Path $Registry) {
            foreach ($VersionKey in Get-ChildItem $Registry) {
                $InstallKey = Join-Path $VersionKey.PSPath 'InstallPath'
                if (Test-Path $InstallKey) {
                    $Properties = Get-ItemProperty $InstallKey
                    if ($Properties.ExecutablePath) { $Candidates += $Properties.ExecutablePath }
                    elseif ($Properties.'(default)') { $Candidates += Join-Path $Properties.'(default)' 'python.exe' }
                }
            }
        }
    }
    foreach ($Pattern in @("$env:LOCALAPPDATA\Programs\Python\Python*\python.exe", "$env:LOCALAPPDATA\Python\pythoncore-*\python.exe", "$env:ProgramFiles\Python*\python.exe", "$env:SystemDrive\Python*\python.exe")) {
        $Candidates += @(Get-Item $Pattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    $Launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($Launcher) {
        $Candidates += @(& $Launcher.Source -0p 2>$null | ForEach-Object {
            if ($_ -match '([A-Za-z]:\\.+\\python(?:3(?:\.\d+)?)?\.exe)\s*$') { $Matches[1] }
        })
    }
    $Found = @()
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { continue }
        if (Test-Path (Join-Path (Split-Path $Candidate) 'conda-meta')) { continue }
        try {
            $Probe = & $Candidate -I -c 'import json,sys; assert sys.version_info >= (3,10); assert sys.prefix == sys.base_prefix; print(json.dumps(dict(executable=sys.executable,version=chr(46).join(map(str,sys.version_info[:3])))))' 2>$null
            if ($LASTEXITCODE -eq 0) { $Found += $Probe | ConvertFrom-Json }
        } catch { continue }
    }
    $Selected = $Found | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1
    if ($Selected) { return $Selected.executable }
    return $null
}

function Install-StandardPython {
    $Architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } elseif ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'win32' }
    $Index = (Invoke-WebRequest 'https://www.python.org/ftp/python/' -UseBasicParsing).Content
    $Versions = [regex]::Matches($Index, 'href="(3\.\d+\.\d+)/"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Descending -Unique
    $Url = $null
    foreach ($Version in $Versions) {
        $Listing = (Invoke-WebRequest "https://www.python.org/ftp/python/$Version/" -UseBasicParsing).Content
        $Filename = if ($Architecture -eq 'win32') { "python-$Version.exe" } else { "python-$Version-$Architecture.exe" }
        if ($Listing.Contains('href="' + $Filename + '"')) {
            $Url = "https://www.python.org/ftp/python/$Version/$Filename"
            break
        }
    }
    if (-not $Url) { throw 'Could not find a stable Python installer on python.org for this architecture.' }
    $Temporary = Join-Path ([IO.Path]::GetTempPath()) ('projtool-python-' + [guid]::NewGuid().ToString() + '.exe')
    try {
        Write-Host "Downloading Python $Version from python.org."
        Invoke-WebRequest $Url -OutFile $Temporary -UseBasicParsing
        $Signature = Get-AuthenticodeSignature -FilePath $Temporary
        if ($Signature.Status -ne 'Valid' -or $Signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') { throw 'The Python installer signature could not be verified.' }
        $Process = Start-Process -FilePath $Temporary -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=1 InstallLauncherAllUsers=0 Include_test=0' -PassThru -Wait
        if ($Process.ExitCode -notin @(0, 3010)) { throw "The Python installer exited with code $($Process.ExitCode)." }
    } finally { Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue }
    $Python = Get-StandardPython
    if (-not $Python) { throw 'Python was installed but could not be located. Reopen PowerShell and rerun this installer.' }
    return $Python
}

function Get-Conda {
    $Candidates = @($env:CONDA_EXE)
    $Command = Get-Command conda.exe -ErrorAction SilentlyContinue
    if ($Command) { $Candidates += $Command.Source }
    foreach ($Parent in @($env:USERPROFILE, $env:ProgramData, $env:LOCALAPPDATA, "$env:LOCALAPPDATA\Programs")) {
        foreach ($Name in @('anaconda3', 'miniconda3', 'miniforge3')) {
            $Candidates += Join-Path $Parent "$Name\Scripts\conda.exe"
        }
    }
    return $Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Get-GitBash {
    $Candidates = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
    foreach ($Registry in @('HKCU:\Software\GitForWindows', 'HKLM:\Software\GitForWindows')) {
        $Install = (Get-ItemProperty $Registry -ErrorAction SilentlyContinue).InstallPath
        if ($Install) { $Candidates += Join-Path $Install 'bin\bash.exe' }
    }
    $Git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($Git) { $Candidates += Join-Path (Split-Path (Split-Path $Git.Source)) 'bin\bash.exe' }
    return $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Install-GitBash {
    $Architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { '64-bit' }
    $Release = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest'
    $Asset = $Release.assets | Where-Object { $_.name -match "^Git-[0-9].*-$Architecture\.exe$" } | Select-Object -First 1
    if (-not $Asset -or $Asset.browser_download_url -notlike 'https://github.com/git-for-windows/git/releases/download/*') { throw 'Could not locate the official Git for Windows installer.' }
    $Temporary = Join-Path ([IO.Path]::GetTempPath()) ('projtool-git-' + [guid]::NewGuid().ToString() + '.exe')
    try {
        Write-Host 'Installing Git for Windows to provide the Bash shell required by ProjTool.'
        Invoke-WebRequest $Asset.browser_download_url -OutFile $Temporary -UseBasicParsing
        if ((Get-AuthenticodeSignature -FilePath $Temporary).Status -ne 'Valid') { throw 'The Git installer signature could not be verified.' }
        $Destination = Join-Path $env:LOCALAPPDATA 'Programs\Git'
        $Process = Start-Process -FilePath $Temporary -ArgumentList "/VERYSILENT /NORESTART /CURRENTUSER /SP- /DIR=`"$Destination`"" -PassThru -Wait
        if ($Process.ExitCode -ne 0) { throw "The Git installer exited with code $($Process.ExitCode)." }
    } finally { Remove-Item -LiteralPath $Temporary -Force -ErrorAction SilentlyContinue }
    $Bash = Get-GitBash
    if (-not $Bash) { throw 'Git Bash was installed but could not be located. Reopen PowerShell and rerun the installer.' }
    return $Bash
}

try {
    $Python = $null
    $Conda = $null
    $Provider = $null
    if ($Component -ne 'julia') {
        while (-not $Python) {
            $Provider = (Read-Host 'What Python install would you like to use? The options are conda or standard, where standard means you have installed Python from python.org, which can be done here for you if desired.').Trim().ToLowerInvariant()
            switch ($Provider) {
                'conda' {
                    $Conda = Get-Conda
                    if (-not $Conda) { Write-Host 'Conda was not found on this machine.'; break }
                    $Base = & $Conda info --base
                    if ($LASTEXITCODE -ne 0) { throw 'Conda could not report its installation directory.' }
                    $Python = Join-Path ($Base | Select-Object -Last 1) 'python.exe'
                    if (-not (Test-Path -LiteralPath $Python)) { Write-Host 'The Conda base Python is missing.'; $Python = $null }
                }
                'standard' {
                    $Python = Get-StandardPython
                    if (-not $Python) {
                        do { $Answer = (Read-Host 'A standard Python 3.10+ installation was not found. Install the newest stable Python from python.org? [yes/no]').Trim().ToLowerInvariant() } until ($Answer -in @('yes', 'y', 'no', 'n'))
                        if ($Answer -in @('yes', 'y')) { $Python = Install-StandardPython }
                    }
                }
                default { Write-Host 'Choose conda or standard.' }
            }
        }
    } else {
        $SavedPython = Join-Path $Config 'python-executable'
        if (Test-Path -LiteralPath $SavedPython) { $Python = (Get-Content -LiteralPath $SavedPython -Raw).Trim() }
        if (-not $Python -or -not (Test-Path -LiteralPath $Python)) { $Python = Get-StandardPython }
        if (-not $Python) { throw 'Run projtool update python first to configure Python.' }
    }
    $Bash = Get-GitBash
    if (-not $Bash) { $Bash = Install-GitBash }
    $SetupArguments = @((Join-Path $Root 'source\configure.py'), '--component', $Component, '--bash', $Bash)
    if ($Component -ne 'julia') {
        $SetupArguments += @('--provider', $Provider, '--python', $Python)
        if ($Provider -eq 'conda') { $SetupArguments += @('--conda', $Conda) }
    }
    & $Python @SetupArguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $Source = Join-Path $Root 'source'
    $env:Path = "$Source;$env:Path"
} catch {
    Write-Error $_
    exit 1
}
