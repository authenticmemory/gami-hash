param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an Administrator PowerShell window in the VM.'
}
foreach ($subcategory in @('Filtering Platform Connection','Filtering Platform Packet Drop')) {
    $policy = (& auditpol.exe /get "/subcategory:$subcategory" /r | Out-String)
    if ($policy -notmatch 'No Auditing') { throw "$subcategory was already enabled; preserve its existing policy before proceeding." }
}
$start = [DateTime]::UtcNow
$start.ToString('o') | Set-Content -LiteralPath (Join-Path $Directory 'attribution-start-utc.txt')
Remove-Item -LiteralPath (Join-Path $Directory 'stop-loopback-listener.flag') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $Directory 'loopback-listener-started.txt') -Force -ErrorAction SilentlyContinue
& auditpol.exe /set '/subcategory:Filtering Platform Connection' /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not enable WFP connection auditing.' }
& auditpol.exe /set '/subcategory:Filtering Platform Packet Drop' /failure:enable | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not enable WFP packet-drop auditing.' }
& pktmon.exe filter remove | Out-Null
foreach ($ip in @('127.0.0.1','::1','192.168.247.1','1.1.1.1','fd00::1','2606:4700:4700::1111')) {
    & pktmon.exe filter add -i $ip | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not add PktMon filter for $ip" }
}
& pktmon.exe start --capture --comp all --type all --pkt-size 128 --file-name (Join-Path $Directory 'phase1-attribution-packets.etl') --file-size 128 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'PktMon did not start.' }
$listener = Join-Path $Directory 'loopback-listener-in-vm.ps1'
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$listener`"") -WindowStyle Hidden -PassThru
$process.Id | Set-Content -LiteralPath (Join-Path $Directory 'loopback-listener-pid.txt')
for ($i=0; $i -lt 40 -and -not (Test-Path -LiteralPath (Join-Path $Directory 'loopback-listener-started.txt')); $i++) {
    Start-Sleep -Milliseconds 250
}
if (-not (Test-Path -LiteralPath (Join-Path $Directory 'loopback-listener-started.txt'))) {
    throw 'Loopback positive-control listener did not start; stop capture and inspect its result.'
}
Write-Host 'Attribution capture and IPv4/IPv6 loopback listeners started. Run the updated probe once, then stop capture.'
