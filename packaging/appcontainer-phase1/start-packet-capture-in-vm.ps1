param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an Administrator PowerShell window.'
}
New-Item -ItemType Directory -Path $Directory -Force | Out-Null
& pktmon filter remove | Out-Null
& pktmon filter add -i 1.1.1.1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not add public-address packet filter' }
& pktmon filter add -i 192.168.247.1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not add private-address packet filter' }
$file = Join-Path $Directory 'phase1-packets.etl'
& pktmon start --capture --comp all --type all --pkt-size 128 --file-name $file --file-size 64 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not start PktMon capture' }
"Capture started UTC=$([DateTime]::UtcNow.ToString('o'))" | Set-Content -LiteralPath (Join-Path $Directory 'packet-capture-phases.txt')
Write-Host 'Capture started. Click Run contained worker in the probe, then run stop-packet-capture-in-vm.ps1 in this window.'
