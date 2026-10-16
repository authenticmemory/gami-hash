param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$events = @(Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    StartTime = (Get-Date).AddHours(-2)
} -ErrorAction SilentlyContinue)
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    eventCount = $events.Count
    countsById = @($events | Group-Object Id | Sort-Object Name | ForEach-Object {
        [ordered]@{ id = [int]$_.Name; count = $_.Count }
    })
    probeEvents = @($events | Where-Object { $_.Message -like '*GamiPhase1Probe*' } |
        Select-Object -First 20 | ForEach-Object {
            [ordered]@{ id = $_.Id; utc = $_.TimeCreated.ToUniversalTime().ToString('o'); recordId = $_.RecordId }
        })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'sysmon-inspection.json') -Encoding UTF8
