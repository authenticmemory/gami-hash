$ErrorActionPreference = 'Stop'

$captureRoot = 'C:\Users\Public\Documents\GamiPhase2ProductCapture'
$etl = Join-Path $captureRoot 'source-write-capture.etl'
$csv = Join-Path $captureRoot 'source-write-capture.csv'
$summary = Join-Path $captureRoot 'capture-summary.txt'

& wpr.exe -stop $etl
if ($LASTEXITCODE -ne 0) {
    throw "WPR FileIO capture failed to stop (exit $LASTEXITCODE)."
}

& tracerpt.exe $etl -of CSV -o $csv -y | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "tracerpt failed to convert the ETL (exit $LASTEXITCODE)."
}

@(
    "stopped_utc=$([DateTime]::UtcNow.ToString('O'))"
    "etl=$etl"
    "csv=$csv"
    "etl_bytes=$((Get-Item -LiteralPath $etl).Length)"
    "csv_bytes=$((Get-Item -LiteralPath $csv).Length)"
) | Set-Content -LiteralPath $summary

Get-Content -LiteralPath $summary
