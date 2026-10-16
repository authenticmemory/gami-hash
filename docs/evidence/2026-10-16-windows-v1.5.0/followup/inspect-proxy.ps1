$dir = 'C:\Users\Public\Documents\GamiHashTest'
$app = @(Get-CimInstance Win32_Process -Filter "Name='GAMI Hash.exe'" | Select-Object ProcessId,ParentProcessId,CreationDate,CommandLine)
$webview = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" | Where-Object CommandLine -Like '*GAMI Hash.exe*' | Select-Object ProcessId,ParentProcessId,CreationDate,CommandLine)
[pscustomobject]@{
    CheckedUTC = [DateTime]::UtcNow.ToString('o')
    AppProcesses = $app
    WebViewProcesses = $webview
    PktmonStatus = (& pktmon.exe status | Out-String)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'proxy-inspect.json') -Encoding UTF8
