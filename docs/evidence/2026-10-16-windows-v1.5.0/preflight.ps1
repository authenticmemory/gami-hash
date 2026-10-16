$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$drive = Get-PSDrive C
$webviewProcesses = @(Get-Process msedgewebview2 -ErrorAction SilentlyContinue)
$webviewInstallers = @(
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.name -match 'WebView2' } |
        Select-Object name,pv
)
[pscustomobject]@{
    TimeUTC = [DateTime]::UtcNow.ToString('o')
    FreeGB = [math]::Round($drive.Free / 1GB, 2)
    SysmonService = (Get-Service Sysmon64).Status.ToString()
    WebView2RunningCount = $webviewProcesses.Count
    WebView2InstallRegistry = $webviewInstallers
    PktmonHelp = (& pktmon.exe start help 2>&1 | Out-String)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'preflight.json') -Encoding UTF8
