param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an Administrator PowerShell window.'
}
$name = 'GamiPhase1Loopback'
$root = Join-Path $Directory 'loopback-smb-fixture'
$source = Join-Path $root 'source'
$output = Join-Path $root 'output'
New-Item -ItemType Directory -Path $source,$output -Force | Out-Null
Copy-Item -Path (Join-Path $Directory 'local-fixture\source\*') -Destination $source -Recurse -Force
$account = "$env:COMPUTERNAME\gami_runner"
$existing = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Path -ne $root) { throw "Share $name already points elsewhere: $($existing.Path)" }
} else {
    New-SmbShare -Name $name -Path $root -ChangeAccess $account | Out-Null
}
$unc = "\\$env:COMPUTERNAME\$name"
Write-Host "UNC source: $unc\source"
Write-Host "UNC output: $unc\output"
Write-Host "Share accessible to current account: $(Test-Path -LiteralPath $unc)"
Write-Host 'This is an SMB loopback pretest, not a remote institution/provider test.'
