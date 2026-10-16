$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$exe = Join-Path $dir 'Procmon64.exe'
$pml = Join-Path $dir 'gami-file-access.pml'
$csv = Join-Path $dir 'gami-file-access-full.csv'
if (Test-Path -LiteralPath $csv) { throw 'Procmon CSV already exists.' }
$args = '/AcceptEula /OpenLog "{0}" /SaveAs "{1}" /Quiet' -f $pml,$csv
$process = Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(180000)) {
    throw 'Procmon CSV export exceeded 180 seconds.'
}
Start-Sleep -Seconds 2
if (-not (Test-Path -LiteralPath $csv)) { throw "Procmon CSV was not created; exit $($process.ExitCode)." }
[pscustomobject]@{
    ExportedUTC = [DateTime]::UtcNow.ToString('o')
    ExitCode = $process.ExitCode
    CsvBytes = (Get-Item -LiteralPath $csv).Length
    Header = [IO.File]::ReadLines($csv) | Select-Object -First 1
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'procmon-export.json') -Encoding UTF8
