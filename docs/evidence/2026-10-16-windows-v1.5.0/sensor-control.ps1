$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$start = [DateTime]::UtcNow
$dns = Resolve-DnsName -Name 'example.com' -Type A -ErrorAction Stop
$client = [Net.Sockets.TcpClient]::new()
try {
    $client.Connect('example.com', 443)
} finally {
    $client.Dispose()
}
Start-Sleep -Seconds 3
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    StartTime = $start.ToLocalTime()
} -ErrorAction Stop | Where-Object { $_.Id -in 1, 3, 22 }
$records = foreach ($event in $events) {
    [xml]$xml = $event.ToXml()
    $data = @{}
    foreach ($item in $xml.Event.EventData.Data) { $data[[string]$item.Name] = [string]$item.'#text' }
    [pscustomobject]@{
        TimeCreatedUTC = $event.TimeCreated.ToUniversalTime().ToString('o')
        EventId = $event.Id
        Image = $data.Image
        ProcessId = $data.ProcessId
        QueryName = $data.QueryName
        DestinationIp = $data.DestinationIp
        DestinationPort = $data.DestinationPort
        Data = $data
    }
}
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'sensor-control-events.json') -Encoding UTF8
[pscustomobject]@{
    ControlStartUTC = $start.ToString('o')
    DnsAnswerCount = @($dns).Count
    SysmonEventCount = @($records).Count
    SawDnsQuery = [bool](@($records | Where-Object { $_.EventId -eq 22 -and $_.QueryName -eq 'example.com' }).Count)
    SawTcpConnect = [bool](@($records | Where-Object { $_.EventId -eq 3 -and $_.DestinationPort -eq '443' }).Count)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'sensor-control-result.json') -Encoding UTF8
