param([Parameter(Mandatory)][ValidateSet('idle','local-hash')][string]$Scenario)
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Public\Documents\GamiHashNativeTest'
$evidence = Join-Path $root "evidence-$Scenario"
$start = [DateTime]::Parse((Get-Content -LiteralPath (Join-Path $evidence 'start-utc.txt')))
$end = Get-Date
$end.ToString('o') | Set-Content -LiteralPath (Join-Path $evidence 'end-utc.txt') -Encoding ascii

& pktmon.exe stop | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pktmon stop failed: $LASTEXITCODE" }
& pktmon.exe etl2pcap (Join-Path $evidence 'network.etl') --out (Join-Path $evidence 'network.pcapng') | Out-Null

$events = @(Get-WinEvent -FilterHashtable @{
  LogName='Microsoft-Windows-Sysmon/Operational'; Id=1,3,22; StartTime=$start; EndTime=$end
} -ErrorAction SilentlyContinue | ForEach-Object {
  $xml = [xml]$_.ToXml(); $data=@{}
  foreach($item in $xml.Event.EventData.Data){$data[$item.Name]=[string]$item.'#text'}
  [pscustomobject]@{ TimeCreated=$_.TimeCreated.ToUniversalTime().ToString('o'); Id=$_.Id; Data=$data }
})
$events | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'sysmon-all.json') -Encoding UTF8
$gami = @($events | Where-Object {
  $_.Data.Image -like '*\GamiHash.WpfSpike.exe' -or $_.Data.Image -like '*\GamiHashEngine.exe' -or
  $_.Data.ParentImage -like '*\GamiHash.WpfSpike.exe'
})
$gami | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'sysmon-gami.json') -Encoding UTF8

$processes = @(Get-CimInstance Win32_Process | Where-Object Name -in @('GamiHash.WpfSpike.exe','GamiHashEngine.exe') |
  Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine)
$summary = [ordered]@{
  scenario=$Scenario; startUtc=$start.ToString('o'); endUtc=$end.ToString('o')
  packetCaptureBytes=(Get-Item -LiteralPath (Join-Path $evidence 'network.pcapng')).Length
  sysmonGamiEvents=$gami.Count
  gamiNetworkEvents=@($gami | Where-Object Id -eq 3).Count
  gamiDnsEvents=@($gami | Where-Object Id -eq 22).Count
  processes=$processes
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $evidence 'summary.json')
