param(
    [string]$OutputDirectory = 'C:\Users\Public\Documents\GamiHashAppContainerEvidence',
    [int]$LookbackHours = 4
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$start = (Get-Date).AddHours(-$LookbackHours)

function Convert-Event($eventRecord) {
    [xml]$xml = $eventRecord.ToXml()
    $fields = [ordered]@{}
    foreach ($field in @($xml.Event.EventData.Data)) {
        if ($field.Name) { $fields[$field.Name] = $field.'#text' }
    }
    [ordered]@{
        id = $eventRecord.Id
        recordId = $eventRecord.RecordId
        utc = $eventRecord.TimeCreated.ToUniversalTime().ToString('o')
        fields = $fields
    }
}

$events = @(Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    Id = 1, 5
    StartTime = $start
} -ErrorAction Stop | Where-Object {
    $_.Message -like '*GamiHash.exe*' -or
    $_.Message -like '*AuthenticMemory.GAMIHash.Windows*'
} | ForEach-Object { Convert-Event $_ })

[ordered]@{
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    lookbackStartUtc = $start.ToUniversalTime().ToString('o')
    eventCount = $events.Count
    events = $events
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'sysmon-processes.json') -Encoding UTF8
