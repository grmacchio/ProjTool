$ToolArguments = @($args)
$ErrorActionPreference = 'Stop'
$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $env:USERPROFILE '.config' }
$SettingsFile = Join-Path $ConfigHome 'projtool\config.json'
if (-not (Test-Path -LiteralPath $SettingsFile)) { throw 'Run the ProjTool installer first.' }
$Settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $Settings.bash)) { throw 'Git Bash is missing. Restore Git for Windows and rerun the installer.' }
$env:HOME = $env:USERPROFILE
$Script = (Join-Path $PSScriptRoot 'projtool').Replace('\', '/')
function ConvertTo-NativeArgument([string]$Value) {
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
$Start = New-Object System.Diagnostics.ProcessStartInfo
$Start.FileName = $Settings.bash
$Start.UseShellExecute = $false
$Start.WorkingDirectory = (Get-Location).Path
$Start.Arguments = ((@($Script) + @($ToolArguments) | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
$Process = [System.Diagnostics.Process]::Start($Start)
$Process.WaitForExit()
exit $Process.ExitCode
