param([string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from an Administrator PowerShell session.'
}
$name = 'GamiPhase1Remote'
$user = 'gami_phase1_smb'
$rule = 'GAMI Phase 1 temporary SMB from VMnet8 guest'
$firewall = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
if ($firewall) { $firewall | Remove-NetFirewallRule }
$share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
if ($share) { $share | Remove-SmbShare -Force }
$account = Get-LocalUser -Name $user -ErrorAction SilentlyContinue
if ($account) { $account | Remove-LocalUser }
$secretFile = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build\bin\appcontainer-phase1\remote-smb-secret.txt'))
$expectedParent = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build\bin\appcontainer-phase1'))
if ([IO.Path]::GetDirectoryName($secretFile) -ne $expectedParent) { throw 'Secret path is outside the expected build directory.' }
if (Test-Path -LiteralPath $secretFile) { Remove-Item -LiteralPath $secretFile -Force }
Write-Host 'Temporary SMB share, firewall rule, account and test secret removed. Fixture files remain in the ignored build directory.'
