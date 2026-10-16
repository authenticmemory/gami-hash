$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$input = Join-Path $dir 'gami-file-access.pml'
$archive = Join-Path $dir 'gami-file-access.zip'
if (-not (Test-Path -LiteralPath $input)) { throw 'Procmon backing file missing.' }
if (Test-Path -LiteralPath $archive) { throw 'Procmon archive already exists.' }
Compress-Archive -LiteralPath $input -DestinationPath $archive -CompressionLevel Optimal
[pscustomobject]@{
    PackedUTC = [DateTime]::UtcNow.ToString('o')
    SourceBytes = (Get-Item -LiteralPath $input).Length
    SourceSHA256 = (Get-FileHash -LiteralPath $input -Algorithm SHA256).Hash
    ArchiveBytes = (Get-Item -LiteralPath $archive).Length
    ArchiveSHA256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'procmon-archive.json') -Encoding UTF8
