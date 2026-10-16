$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$source = Join-Path $dir 'source'
$output = Join-Path $dir 'output\stable.csv'
$rows = @(Import-Csv -LiteralPath $output)
$expected = 'relative_path,size_bytes,file_hash,mtime_utc,source_record_id'
$actual = $rows[0].PSObject.Properties.Name -join ','
if ($actual -ne $expected) { throw "Unexpected CSV columns: $actual" }
if ($rows.Count -ne 514) { throw "Expected 514 rows; got $($rows.Count)" }
$mismatches = @()
foreach ($row in $rows) {
    $file = Join-Path $source $row.relative_path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $mismatches += "Missing: $($row.relative_path)"; continue }
    $item = Get-Item -LiteralPath $file
    $hash = 'sha256:' + (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($row.file_hash -ne $hash) { $mismatches += "Hash: $($row.relative_path)" }
    if ([long]$row.size_bytes -ne $item.Length) { $mismatches += "Size: $($row.relative_path)" }
    if ($row.source_record_id -cne $row.relative_path) { $mismatches += "Record ID: $($row.relative_path)" }
}
[pscustomobject]@{
    VerifiedUTC = [DateTime]::UtcNow.ToString('o')
    Manifest = $output
    ManifestSHA256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    Columns = $actual
    Rows = $rows.Count
    MismatchCount = $mismatches.Count
    Mismatches = $mismatches
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'stable-verification.json') -Encoding UTF8
if ($mismatches.Count) { throw "Stable verification found $($mismatches.Count) mismatches." }
