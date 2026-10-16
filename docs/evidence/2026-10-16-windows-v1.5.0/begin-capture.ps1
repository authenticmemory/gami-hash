$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$capture = Join-Path $dir 'gami-network.etl'
$markers = Join-Path $dir 'phase-markers.csv'
if (Test-Path -LiteralPath $capture) { throw 'Capture file already exists.' }
if (Test-Path -LiteralPath $markers) { throw 'Phase marker file already exists.' }
& pktmon.exe filter remove | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not clear pktmon filters.' }
& pktmon.exe start --capture --comp nics --pkt-size 128 --file-name $capture --file-size 128 --log-mode circular
if ($LASTEXITCODE -ne 0) { throw "pktmon start failed: $LASTEXITCODE" }
@([pscustomobject]@{ UTC = [DateTime]::UtcNow.ToString('o'); Phase = 'capture_started' }) |
    Export-Csv -LiteralPath $markers -NoTypeInformation
& pktmon.exe status | Out-File -LiteralPath (Join-Path $dir 'pktmon-status-start.txt') -Encoding UTF8
