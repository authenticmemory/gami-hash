$dir = 'C:\Users\Public\Documents\GamiHashTest'
$files = @(Get-ChildItem -LiteralPath $dir -Filter 'gami-file-access*.pml' -File | Select-Object Name,Length)
[pscustomobject]@{
    UTC = [DateTime]::UtcNow.ToString('o')
    FreeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    ProcmonFiles = $files
    PacketTraceBytes = (Get-Item -LiteralPath (Join-Path $dir 'gami-network.etl')).Length
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'space-check.json') -Encoding UTF8
