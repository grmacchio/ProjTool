$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Source = Join-Path $Root 'source'
$ConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $env:USERPROFILE '.config' }
$Config = Join-Path $ConfigHome 'projtool'
if ($Root -eq $env:USERPROFILE -or $Root -eq [IO.Path]::GetPathRoot($Root) -or -not (Test-Path (Join-Path $Root 'source\projtool'))) { throw 'Could not identify the ProjTool repository safely.' }
$RegisteredFile = Join-Path $Config 'root'
if (Test-Path -LiteralPath $RegisteredFile) {
    $Registered = (Get-Content -LiteralPath $RegisteredFile -Raw).Trim()
    if ($Registered -ne $Root) { throw "A different ProjTool directory is registered: $Registered" }
}
Write-Host "This will permanently delete $Root and everything inside it, including uncommitted files."
if ((Read-Host 'Type DELETE to uninstall ProjTool') -cne 'DELETE') { Write-Host 'Uninstall cancelled.'; exit 0 }

$Registry = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
try {
    $Value = $Registry.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $Entries = @($Value -split ';' | Where-Object { $_ -and [Environment]::ExpandEnvironmentVariables($_.Trim('"')).TrimEnd('\', '/') -ine $Source })
    $Kind = if ($Registry.GetValueNames() -contains 'Path') { $Registry.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $Registry.SetValue('Path', ($Entries -join ';'), $Kind)
} finally { if ($Registry) { $Registry.Dispose() } }
$env:Path = (($env:Path -split ';') | Where-Object { $_.Trim('"').TrimEnd('\', '/') -ine $Source }) -join ';'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ProjToolEnvironment { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r); }'
$Result = [UIntPtr]::Zero
[void][ProjToolEnvironment]::SendMessageTimeout([IntPtr]65535, 26, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$Result)
Set-Location $env:USERPROFILE
Remove-Item -LiteralPath $Root -Recurse -Force
if (Test-Path -LiteralPath $RegisteredFile) { Remove-Item -LiteralPath $Config -Recurse -Force }
Write-Host 'The ProjTool directory is deleted and the projtool command is no longer in PATH.'
Write-Host 'The dependencies are not deleted so as not to interfere with unrelated code on your machine.'
Write-Host 'Open a new terminal and restart VS Code to refresh PATH.'
