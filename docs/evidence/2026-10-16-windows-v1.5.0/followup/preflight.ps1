$dir = 'C:\Users\Public\Documents\GamiHashTest'
[pscustomobject]@{
    CheckedUTC = [DateTime]::UtcNow.ToString('o')
    GamiProcesses = @(Get-Process -Name 'GAMI Hash' -ErrorAction SilentlyContinue | Select-Object Id,ProcessName)
    WebViewProcesses = @(Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue).Count
    NetLogExists = Test-Path -LiteralPath (Join-Path $dir 'netlog-followup.json')
    PacketExists = Test-Path -LiteralPath (Join-Path $dir 'packet-followup.etl')
    Policy = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments' -Name 'GAMI Hash.exe' -ErrorAction SilentlyContinue).'GAMI Hash.exe'
    PktmonStatus = (& pktmon.exe status | Out-String)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'followup-preflight.json') -Encoding UTF8
