param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an Administrator PowerShell window.'
}
$phases = Join-Path $Directory 'packet-capture-phases.txt'
"Positive control started UTC=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $phases
$controlResult = 'not attempted'
try {
    $socket = New-Object System.Net.Sockets.UdpClient
    try {
        $sent = $socket.Send([byte[]](0x47,0x41,0x4d,0x49,0x2d,0x43,0x54,0x52,0x4c),9,'1.1.1.1',53)
        $controlResult = "sendto returned $sent bytes"
    } finally { $socket.Dispose() }
    Start-Sleep -Seconds 2
} catch {
    $controlResult = "sendto failed: $($_.Exception.Message)"
} finally {
    "Positive control: $controlResult" | Add-Content -LiteralPath $phases
    "Capture stopped UTC=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $phases
    & pktmon stop | Out-Null
}
if ($LASTEXITCODE -ne 0) { throw 'PktMon stop failed' }
& pktmon etl2txt (Join-Path $Directory 'phase1-packets.etl') --out (Join-Path $Directory 'phase1-packets.txt') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'PktMon text conversion failed' }
Write-Host 'Capture stopped and converted. Leave the files in GamiPhase1Probe for collection.'
