param(
    [Parameter(Mandatory)] [string]$GuestIPv4,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from an Administrator PowerShell session.'
}
if ($GuestIPv4 -notmatch '^192\.168\.247\.\d{1,3}$') { throw 'GuestIPv4 must be on the VMware VMnet8 subnet.' }
$name = 'GamiPhase1Remote'
$user = 'gami_phase1_smb'
$rule = 'GAMI Phase 1 temporary SMB from VMnet8 guest'
$dir = Join-Path $RepositoryRoot 'build\bin\appcontainer-phase1\remote-smb-fixture'
$secretFile = Join-Path $RepositoryRoot 'build\bin\appcontainer-phase1\remote-smb-secret.txt'
if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) { throw "Local user $user already exists; refusing to alter it." }
if (Get-SmbShare -Name $name -ErrorAction SilentlyContinue) { throw "Share $name already exists; refusing to alter it." }
if (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue) { throw "Firewall rule $rule already exists; refusing to alter it." }
$fixtureExists = Test-Path -LiteralPath $dir
$secretExists = Test-Path -LiteralPath $secretFile
if ($fixtureExists -ne $secretExists) { throw 'Fixture and secret must either both exist or both be absent; refusing partial recovery.' }
if ($fixtureExists -and -not (Test-Path -LiteralPath (Join-Path $dir 'expected.json'))) { throw 'Existing fixture lacks expected.json.' }

try {
    if (-not $fixtureExists) { & (Join-Path $RepositoryRoot 'docs\fixtures\windows-phase0\create-local-fixture.ps1') -Directory $dir }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'expected.json'))) { throw 'Fixture generation failed.' }
    if ($secretExists) {
        $password = [IO.File]::ReadAllText($secretFile).Trim()
    } else {
        $bytes = New-Object byte[] 24
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $password = 'Aa!9' + [BitConverter]::ToString($bytes).Replace('-','')
        $password | Set-Content -LiteralPath $secretFile -NoNewline -Encoding ASCII
    }
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    New-LocalUser -Name $user -Password $securePassword -Description 'Temporary GAMI Phase 1 SMB test' -PasswordNeverExpires | Out-Null
    $account = "$env:COMPUTERNAME\$user"
    & icacls $dir /grant "${account}:(OI)(CI)M" /T | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not grant fixture NTFS access.' }
    New-SmbShare -Name $name -Path $dir -ChangeAccess $account -EncryptData $true -CachingMode None -Description 'Temporary GAMI Phase 1 VM test share' | Out-Null
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445 -LocalAddress 192.168.247.1 -RemoteAddress $GuestIPv4 -InterfaceAlias 'VMware Network Adapter VMnet8' -Profile Any | Out-Null
    Write-Host "Share=\\192.168.247.1\$name"
    Write-Host "Account=$account"
    Write-Host "GuestIPv4=$GuestIPv4"
    Write-Host "SecretFile=$secretFile (private, remove after test)"
} catch {
    $firewall = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($firewall) { $firewall | Remove-NetFirewallRule }
    $share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($share) { $share | Remove-SmbShare -Force }
    $account = Get-LocalUser -Name $user -ErrorAction SilentlyContinue
    if ($account) { $account | Remove-LocalUser }
    throw
}

