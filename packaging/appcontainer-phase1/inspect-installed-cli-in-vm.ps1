param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$cli = 'C:\Users\tech\AppData\Local\Programs\Authentic Memory Hashing Tool\gami-hash.exe'
$result = [ordered]@{
    path = $cli
    exists = (Test-Path -LiteralPath $cli -PathType Leaf)
}
if ($result.exists) {
    $item = Get-Item -LiteralPath $cli
    $result.sizeBytes = $item.Length
    $result.sha256 = (Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.signatureStatus = (Get-AuthenticodeSignature -LiteralPath $cli).Status.ToString()
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Directory 'installed-cli-inspection.json') -Encoding UTF8
