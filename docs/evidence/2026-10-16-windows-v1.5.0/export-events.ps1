$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$markers = Import-Csv -LiteralPath (Join-Path $dir 'phase-markers.csv')
$start = [DateTime]::Parse($markers[0].UTC).ToLocalTime()
$end = [DateTime]::Parse(($markers | Where-Object Phase -eq 'capture_stopped' | Select-Object -Last 1).UTC).ToLocalTime()
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    StartTime = $start
    EndTime = $end
} -ErrorAction Stop | Where-Object { $_.Id -in 1,3,22 }
$records = foreach ($event in $events) {
    [xml]$xml = $event.ToXml()
    $data = @{}
    foreach ($item in $xml.Event.EventData.Data) { $data[[string]$item.Name] = [string]$item.'#text' }
    [pscustomobject]@{
        TimeUTC = $event.TimeCreated.ToUniversalTime().ToString('o')
        EventId = $event.Id
        ProcessGuid = $data.ProcessGuid
        ParentProcessGuid = $data.ParentProcessGuid
        ProcessId = $data.ProcessId
        ParentProcessId = $data.ParentProcessId
        Image = $data.Image
        ParentImage = $data.ParentImage
        CommandLine = $data.CommandLine
        QueryName = $data.QueryName
        QueryStatus = $data.QueryStatus
        QueryResults = $data.QueryResults
        Protocol = $data.Protocol
        SourceIp = $data.SourceIp
        SourcePort = $data.SourcePort
        DestinationIp = $data.DestinationIp
        DestinationPort = $data.DestinationPort
        Initiated = $data.Initiated
    }
}
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'sysmon-events.json') -Encoding UTF8
[pscustomobject]@{
    ExportUTC = [DateTime]::UtcNow.ToString('o')
    EventCount = @($records).Count
    ProcessCreates = @($records | Where-Object EventId -eq 1).Count
    Connections = @($records | Where-Object EventId -eq 3).Count
    DnsQueries = @($records | Where-Object EventId -eq 22).Count
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'sysmon-event-counts.json') -Encoding UTF8
