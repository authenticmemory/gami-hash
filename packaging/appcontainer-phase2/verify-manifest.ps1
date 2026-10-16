param(
    [Parameter(Mandatory)][string]$Manifest,
    [Parameter(Mandatory)][string]$Expected
)

$ErrorActionPreference = 'Stop'
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$expectedPath = (Resolve-Path -LiteralPath $Expected).Path
$bytes = [IO.File]::ReadAllBytes($manifestPath)
if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
    throw 'Manifest is missing its UTF-8 BOM'
}
$text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
if (-not $text.Contains("`r`n") -or $text.Replace("`r`n", '').Contains("`n")) {
    throw 'Manifest must use CRLF row endings'
}
$header = ($text -split "`r`n", 2)[0]
if ($header -ne 'relative_path,size_bytes,file_hash,mtime_utc,source_record_id') {
    throw "Wrong CSV header: $header"
}
$rows = Import-Csv -LiteralPath $manifestPath
$expectedRows = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$oracle = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($item in $expectedRows) {
    if ($oracle.ContainsKey([string]$item.relative_path)) {
        throw "Duplicate expected path: $($item.relative_path)"
    }
    $oracle.Add([string]$item.relative_path, $item)
}
$mismatches = [Collections.Generic.List[string]]::new()
foreach ($row in $rows) {
    $path = [string]$row.relative_path
    if (-not $seen.Add($path)) { $mismatches.Add("duplicate: $path"); continue }
    $item = $null
    if (-not $oracle.TryGetValue($path, [ref]$item)) {
        $mismatches.Add("unexpected: $path")
        continue
    }
    if ([string]$row.size_bytes -ne [string]$item.size_bytes) { $mismatches.Add("size: $path") }
    if ([string]$row.file_hash -ne ('sha256:' + [string]$item.sha256)) { $mismatches.Add("hash: $path") }
    if ([string]$row.source_record_id -cne $path) { $mismatches.Add("record ID: $path") }
    if ([string]$row.mtime_utc -cnotmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$') {
        $mismatches.Add("UTC mtime: $path")
    }
}
foreach ($path in $oracle.Keys) {
    if (-not $seen.Contains($path)) { $mismatches.Add("missing: $path") }
}
if ($mismatches.Count) { throw ($mismatches -join '; ') }
[pscustomobject]@{
    Rows = @($rows).Count
    Expected = $oracle.Count
    Mismatches = 0
    ManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
