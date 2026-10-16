$dir = 'C:\Users\Public\Documents\GamiHashTest'
$netlog = Join-Path $dir 'netlog-followup.json'
$app = @(Get-CimInstance Win32_Process -Filter "Name='GAMI Hash.exe'")
$webview = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
    Where-Object CommandLine -Like '*GAMI Hash.exe*' |
    Select-Object ProcessId,ParentProcessId,CommandLine)
[pscustomobject]@{
    CheckedUTC = [DateTime]::UtcNow.ToString('o')
    AppProcesses = @($app | Select-Object ProcessId,ParentProcessId,CommandLine)
    WebViewProcesses = $webview
    NetLogExists = Test-Path -LiteralPath $netlog
    NetLogBytes = if (Test-Path -LiteralPath $netlog) { (Get-Item -LiteralPath $netlog).Length } else { 0 }
    PktmonStatus = (& pktmon.exe status | Out-String)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'netlog-inspect.json') -Encoding UTF8
