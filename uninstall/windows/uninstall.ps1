$ErrorActionPreference = 'Stop'
$stateDirectory = Join-Path $env:USERPROFILE '.config\projtool'
if ($env:XDG_CONFIG_HOME) { $stateDirectory = Join-Path $env:XDG_CONFIG_HOME 'projtool' }
$stateFile = Join-Path $stateDirectory 'install.json'
if (-not (Test-Path $stateFile)) { Write-Host 'No launcher installation found. From the ProjTool folder, use bash uninstall/mac/uninstall.sh for an older alias installation.'; exit 0 }
$state = Get-Content $stateFile -Raw | ConvertFrom-Json
foreach ($name in @('projtool', 'projtool.cmd')) {
    $launcher = Join-Path $state.binDirectory $name
    if (Test-Path $launcher) {
        if (-not ([IO.File]::ReadAllText($launcher).Contains('PROJTOOL_LAUNCHER=1'))) { throw "Refusing to remove an unrelated file: $launcher" }
        Remove-Item $launcher
    }
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ -and $state.addedPaths -inotcontains $_ })
[Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
if ($state.pythonEnvironment -and (Test-Path $state.pythonEnvironment)) {
    $expected = Join-Path (Split-Path $state.binDirectory) 'python'
    if ($state.pythonEnvironment -ine $expected -or -not (Test-Path (Join-Path $expected '.projtool-owned'))) { throw 'Refusing to remove an unmanaged Python environment.' }
    Remove-Item -LiteralPath $expected -Recurse -Force
}
Remove-Item $stateFile
if (@(Get-ChildItem $state.binDirectory -Force).Count -eq 0) { Remove-Item $state.binDirectory }
if (@(Get-ChildItem $stateDirectory -Force).Count -eq 0) { Remove-Item $stateDirectory }
Write-Host 'Uninstalled projtool. The managed Python environment was removed. Shared runtimes and packages are retained. Restart terminals and VS Code.'
