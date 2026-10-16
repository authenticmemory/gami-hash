param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$root = '\\GAMI-HASH-VM\GamiPhase1Loopback\source'
$result = @(Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object {
    [pscustomobject]@{
        relative_path = $_.FullName.Substring($root.Length + 1).Replace('\','/')
        size_bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
ConvertTo-Json -InputObject $result -Depth 4 |
    Set-Content -LiteralPath (Join-Path $Directory 'phase2-smb-inventory.json') -Encoding UTF8
