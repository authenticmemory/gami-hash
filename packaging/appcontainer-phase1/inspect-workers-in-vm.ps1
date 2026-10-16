param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$processes = @(Get-Process GamiPhase1Probe -ErrorAction SilentlyContinue | ForEach-Object {
    [ordered]@{
        pid = $_.Id
        startUtc = $_.StartTime.ToUniversalTime().ToString('o')
        cpuSeconds = $_.CPU
        handles = $_.HandleCount
        workingSet = $_.WorkingSet64
        hasMainWindow = $_.MainWindowHandle -ne [IntPtr]::Zero
    }
})
$cloudOutput = 'G:\My Drive\gami-test-destination\phase1-probe.csv'
$remoteOutput = '\\192.168.247.1\GamiPhase1Remote\output\phase1-probe.csv'
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    processes = $processes
    cloudOutputExists = Test-Path -LiteralPath $cloudOutput
    cloudOutputLength = if (Test-Path -LiteralPath $cloudOutput) { (Get-Item -LiteralPath $cloudOutput).Length } else { $null }
    remoteOutputExists = Test-Path -LiteralPath $remoteOutput
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Directory 'workers-inspection.json') -Encoding UTF8
