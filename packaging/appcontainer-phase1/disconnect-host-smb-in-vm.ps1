$ErrorActionPreference = 'Stop'
$mapping = Get-SmbMapping -LocalPath 'R:' -ErrorAction SilentlyContinue
if ($mapping -and $mapping.RemotePath -eq '\\192.168.247.1\GamiPhase1Remote') {
    & net.exe use R: /delete /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not remove the test R: mapping.' }
}
& cmdkey.exe /delete:192.168.247.1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not remove the stored test credential.' }
Write-Host 'Stored test credential removed; matching R: mapping removed if present.'
