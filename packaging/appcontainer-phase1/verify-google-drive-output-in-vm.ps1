param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$source = 'G:\My Drive\gami-test'
$csv = 'G:\My Drive\gami-test-destination\phase1-probe.csv'
$rows = @(Import-Csv -LiteralPath $csv -Encoding UTF8)
$mismatches = New-Object System.Collections.Generic.List[string]
foreach ($row in $rows) {
    $relative = $row.relative_path.Replace('/','\')
    $path = Join-Path $source $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $mismatches.Add("missing: $relative"); continue }
    $item = Get-Item -LiteralPath $path
    if ([long]$row.size_bytes -ne $item.Length) { $mismatches.Add("size: $relative"); continue }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($row.file_hash -ne "sha256:$hash") { $mismatches.Add("hash: $relative") }
}
$visibleFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) })
$result = [ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    csvRows = $rows.Count
    distinctPaths = @($rows.relative_path | Sort-Object -Unique).Count
    visibleSourceFiles = $visibleFiles.Count
    mismatchCount = $mismatches.Count
    mismatches = @($mismatches)
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Directory 'google-drive-verification.json') -Encoding UTF8
