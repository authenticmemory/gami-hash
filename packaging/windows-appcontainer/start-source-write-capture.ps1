$ErrorActionPreference = 'Stop'

$captureRoot = 'C:\Users\Public\Documents\GamiPhase2ProductCapture'
New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null

# WPR writes its benign "no recording is running" result to stderr. Invoke it
# through cmd so PowerShell's native-error promotion cannot abort this script.
& cmd.exe /d /c "wpr.exe -cancel >nul 2>&1"
& wpr.exe -start FileIO -filemode
if ($LASTEXITCODE -ne 0) {
    throw "WPR FileIO capture failed to start (exit $LASTEXITCODE)."
}

Set-Content -LiteralPath (Join-Path $captureRoot 'started-utc.txt') -Value ([DateTime]::UtcNow.ToString('O'))
Write-Host 'FileIO capture started. Run the local, SMB, and Google Drive product tests, then run stop-source-write-capture.ps1.'
