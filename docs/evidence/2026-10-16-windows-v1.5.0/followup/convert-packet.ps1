$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
& pktmon.exe etl2txt (Join-Path $dir 'packet-proxy.etl') --out (Join-Path $dir 'packet-proxy.txt') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon etl2txt failed.' }
