param([Parameter(Mandatory)][ValidateSet('idle','local-hash','unc-smb','mapped-drive','cloud-cached','cloud-online-only')][string]$Scenario)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$evidence = Join-Path $root "evidence-$Scenario"
New-Item -ItemType Directory -Force $evidence | Out-Null
foreach ($name in @('network.etl','network.pcapng','sysmon-all.json','sysmon-gami.json','summary.json')) {
  Remove-Item -LiteralPath (Join-Path $evidence $name) -Force -ErrorAction SilentlyContinue
}
$sysmon = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Where-Object Status -eq Running)
if ($sysmon.Count -eq 0) { throw 'Sysmon is not installed or not running.' }
$channel = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction Stop
if (-not $channel.IsEnabled) { throw 'The Sysmon operational event channel is disabled.' }

Get-Process GamiHash,GamiHashEngine -ErrorAction SilentlyContinue | Stop-Process -Force
try { & pktmon.exe stop 2>$null | Out-Null } catch { }
& pktmon.exe filter remove | Out-Null
$start = Get-Date
$start.ToString('o') | Set-Content -LiteralPath (Join-Path $evidence 'start-utc.txt') -Encoding ascii
& pktmon.exe start --capture --comp nics --pkt-size 256 --file-name (Join-Path $evidence 'network.etl') --file-size 128 --log-mode circular | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pktmon start failed: $LASTEXITCODE" }
$app = "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash\GamiHash.exe"
if (-not (Test-Path -LiteralPath $app)) { throw "Production application is not installed: $app" }
Start-Process $app
Write-Host "CAPTURE STARTED: $Scenario"
