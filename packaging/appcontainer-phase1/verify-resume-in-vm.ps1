param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$fixture = Join-Path $Directory 'resume-fixture'
$source = Join-Path $fixture 'source'
$csv = Join-Path $fixture 'output\phase1-probe.csv'
$rows = @(Import-Csv -LiteralPath $csv -Encoding UTF8)
$files = @(Get-ChildItem -LiteralPath $source -File)
$rowByPath = @{}
$duplicates = 0
foreach ($row in $rows) {
    if ($rowByPath.ContainsKey($row.relative_path)) { $duplicates++ }
    else { $rowByPath[$row.relative_path] = $row }
}
$missing = 0
$sizeMismatches = 0
$hashMismatches = 0
$totalBytes = [long]0
foreach ($file in $files) {
    $row = $rowByPath[$file.Name]
    if ($null -eq $row) { $missing++; continue }
    $totalBytes += $file.Length
    if ([long]$row.size_bytes -ne $file.Length) { $sizeMismatches++ }
    $digest = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($row.file_hash -ne ('sha256:' + $digest)) { $hashMismatches++ }
}
$extra = @($rowByPath.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $source $_) -PathType Leaf) }).Count
$result = [ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    sourceFiles = $files.Count
    csvRows = $rows.Count
    uniqueRows = $rowByPath.Count
    duplicates = $duplicates
    missing = $missing
    extra = $extra
    sizeMismatches = $sizeMismatches
    hashMismatches = $hashMismatches
    totalBytes = $totalBytes
    csvSha256 = (Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'resume-verification.json') -Encoding UTF8
if ($files.Count -ne 1024 -or $rows.Count -ne 1024 -or $duplicates -or $missing -or $extra -or $sizeMismatches -or $hashMismatches -or $totalBytes -ne 268435456) {
    throw "Resume verification failed: $($result | ConvertTo-Json -Compress)"
}
Write-Output 'Resume verification passed: 1024 distinct rows, 256 MiB, zero missing/extra/size/hash mismatches.'
