param([Parameter(Mandatory)][ValidateSet('idle','local-hash')][string]$Scenario)
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Public\Documents\GamiHashNativeTest'
$evidence = Join-Path $root "evidence-$Scenario"
New-Item -ItemType Directory -Force $evidence | Out-Null
foreach ($name in @('network.etl','network.pcapng','sysmon-all.json','sysmon-gami.json','summary.json')) {
  Remove-Item -LiteralPath (Join-Path $evidence $name) -Force -ErrorAction SilentlyContinue
}
$sysmon = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Where-Object Status -eq Running)
if ($sysmon.Count -eq 0) { throw 'Sysmon is not installed or not running.' }
$channel = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction Stop
if (-not $channel.IsEnabled) { throw 'The Sysmon operational event channel is disabled.' }

Get-Process GamiHash.WpfSpike,GamiHashEngine -ErrorAction SilentlyContinue | Stop-Process -Force
try { & pktmon.exe stop 2>$null | Out-Null } catch { }
& pktmon.exe filter remove | Out-Null
$start = Get-Date
$start.ToString('o') | Set-Content -LiteralPath (Join-Path $evidence 'start-utc.txt') -Encoding ascii
& pktmon.exe start --capture --comp nics --pkt-size 256 --file-name (Join-Path $evidence 'network.etl') --file-size 128 --log-mode circular | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pktmon start failed: $LASTEXITCODE" }
Start-Process "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash Native Test\GamiHash.WpfSpike.exe"
Write-Host "CAPTURE STARTED: $Scenario"
