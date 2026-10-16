$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$source = Join-Path $dir 'source'
$stablePath = Join-Path $dir 'output\stable.csv'
$resumePath = Join-Path $dir 'output\cancel.csv'
$stable = @(Import-Csv -LiteralPath $stablePath)
$resumed = @(Import-Csv -LiteralPath $resumePath)
$columns = 'relative_path','size_bytes','file_hash','mtime_utc','source_record_id'
$differences = @(Compare-Object -ReferenceObject $stable -DifferenceObject $resumed -Property $columns)
$missing = @($resumed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $source $_.relative_path) -PathType Leaf) })
[pscustomobject]@{
    VerifiedUTC = [DateTime]::UtcNow.ToString('o')
    StableRows = $stable.Count
    ResumedRows = $resumed.Count
    ResumedManifestSHA256 = (Get-FileHash -LiteralPath $resumePath -Algorithm SHA256).Hash
    DifferentRows = $differences.Count
    MissingSourceRows = $missing.Count
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'resume-verification.json') -Encoding UTF8
if ($stable.Count -ne 514 -or $resumed.Count -ne 514 -or $differences.Count -or $missing.Count) {
    throw 'Resumed manifest differs from the uninterrupted manifest.'
}
