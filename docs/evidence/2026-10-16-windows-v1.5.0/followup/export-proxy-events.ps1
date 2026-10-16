$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$start = [datetime]'2026-10-15T23:49:00Z'
$events = @(Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Sysmon/Operational'; Id=1,3,22; StartTime=$start } -ErrorAction Stop)
$rows = foreach ($event in $events) {
    [xml]$xml = $event.ToXml()
    $data = @{}
    foreach ($node in $xml.Event.EventData.Data) { $data[$node.Name] = $node.'#text' }
    if ($event.Id -eq 3 -or ($event.Id -eq 1 -and ($data.Image -like '*GAMI Hash.exe' -or $data.Image -like '*msedgewebview2.exe'))) {
        [pscustomobject]@{
            TimeUTC = $event.TimeCreated.ToUniversalTime().ToString('o')
            EventId = $event.Id
            Image = $data.Image
            ProcessId = $data.ProcessId
            ProcessGuid = $data.ProcessGuid
            ParentProcessGuid = $data.ParentProcessGuid
            DestinationIp = $data.DestinationIp
            DestinationPort = $data.DestinationPort
            SourcePort = $data.SourcePort
            DestinationHostname = $data.DestinationHostname
            CommandLine = if ($event.Id -eq 1) { $data.CommandLine } else { $null }
        }
    }
}
$rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'sysmon-proxy.json') -Encoding UTF8
