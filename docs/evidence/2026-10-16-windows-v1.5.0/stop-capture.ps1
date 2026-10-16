$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$markers = Join-Path $dir 'phase-markers.csv'
[pscustomobject]@{ UTC = [DateTime]::UtcNow.ToString('o'); Phase = 'capture_stopped' } |
    Export-Csv -LiteralPath $markers -NoTypeInformation -Append
& pktmon.exe status | Out-File -LiteralPath (Join-Path $dir 'pktmon-status-end.txt') -Encoding UTF8
& pktmon.exe stop | Out-File -LiteralPath (Join-Path $dir 'pktmon-stop.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "pktmon stop failed: $LASTEXITCODE" }
& wevtutil.exe epl 'Microsoft-Windows-Sysmon/Operational' (Join-Path $dir 'sysmon-operational.evtx')
if ($LASTEXITCODE -ne 0) { throw "Sysmon export failed: $LASTEXITCODE" }
$files = Get-ChildItem -LiteralPath $dir -File | Where-Object {
    $_.Name -in @('gami-network.etl','sysmon-operational.evtx','phase-markers.csv')
}
$files | Select-Object Name,Length,@{Name='SHA256';Expression={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}} |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $dir 'capture-files.json') -Encoding UTF8
