param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an Administrator PowerShell window in the VM.'
}
$start = [datetime](Get-Content -LiteralPath (Join-Path $Directory 'attribution-start-utc.txt') -Raw)
$control = [ordered]@{}
try {
    foreach ($family in @('IPv4','IPv6')) {
        $address = if ($family -eq 'IPv4') { [Net.IPAddress]::Loopback } else { [Net.IPAddress]::IPv6Loopback }
        try {
            $tcp = [Net.Sockets.TcpClient]::new($address.AddressFamily)
            try { $tcp.Connect($address,48521); $control["TCP$family"] = 'connected' }
            finally { $tcp.Close() }
        } catch { $control["TCP$family"] = $_.Exception.Message }
        try {
            $udp = [Net.Sockets.UdpClient]::new($address.AddressFamily)
            try { $control["UDP$family"] = $udp.Send([byte[]](0x43,0x54,0x52,0x4c),4,[Net.IPEndPoint]::new($address,48521)) }
            finally { $udp.Dispose() }
        } catch { $control["UDP$family"] = $_.Exception.Message }
    }
    Start-Sleep -Seconds 2
    New-Item -ItemType File -Path (Join-Path $Directory 'stop-loopback-listener.flag') -Force | Out-Null
    Start-Sleep -Seconds 1
    $end = [DateTime]::UtcNow
    $end.ToString('o') | Set-Content -LiteralPath (Join-Path $Directory 'attribution-stop-utc.txt')
    & pktmon.exe stop | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'PktMon stop failed.' }
    & pktmon.exe etl2txt (Join-Path $Directory 'phase1-attribution-packets.etl') --out (Join-Path $Directory 'phase1-attribution-packets.txt') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'PktMon text conversion failed.' }

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
    $sysmon = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Sysmon/Operational'; Id = 1,3,5,22; StartTime = $start; EndTime = $end
    } -ErrorAction SilentlyContinue | Where-Object { $_.Message -like '*GamiPhase1Probe*' } | ForEach-Object { Convert-Event $_ })
    $wfp = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Security'; Id = 5152,5156,5157; StartTime = $start; EndTime = $end
    } -ErrorAction SilentlyContinue | ForEach-Object { Convert-Event $_ } |
        Where-Object { $_.fields.Application -like '*GamiPhase1Probe*' -or $_.fields.ApplicationName -like '*GamiPhase1Probe*' })
    $sysmon | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $Directory 'phase1-attribution-sysmon.json') -Encoding UTF8
    $wfp | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $Directory 'phase1-attribution-wfp.json') -Encoding UTF8
    [ordered]@{
        startUtc = $start.ToUniversalTime().ToString('o')
        endUtc = $end.ToString('o')
        controls = $control
        sysmonProbeEvents = $sysmon.Count
        wfpProbeEvents = $wfp.Count
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Directory 'phase1-attribution-summary.json') -Encoding UTF8
    Write-Host "Capture complete: Sysmon probe events=$($sysmon.Count), WFP probe events=$($wfp.Count)."
} finally {
    & auditpol.exe /set '/subcategory:Filtering Platform Connection' /success:disable /failure:disable | Out-Null
    & auditpol.exe /set '/subcategory:Filtering Platform Packet Drop' /success:disable /failure:disable | Out-Null
    & pktmon.exe filter remove | Out-Null
}
