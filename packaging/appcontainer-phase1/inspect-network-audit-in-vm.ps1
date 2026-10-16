param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    account = (whoami)
    filteringPlatformConnection = ((& auditpol.exe /get '/subcategory:Filtering Platform Connection' /r) | Out-String)
    filteringPlatformPacketDrop = ((& auditpol.exe /get '/subcategory:Filtering Platform Packet Drop' /r) | Out-String)
    sysmonServices = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue | Select-Object Name,Status)
    sysmonOperationalLog = (Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IsEnabled)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Directory 'network-audit-inspection.json') -Encoding UTF8
