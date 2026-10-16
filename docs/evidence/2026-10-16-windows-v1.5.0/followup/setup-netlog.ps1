$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
trap {
    $_ | Format-List * -Force | Out-File -LiteralPath (Join-Path $dir 'netlog-setup-error.txt') -Encoding UTF8
    exit 1
}
$netlog = Join-Path $dir 'netlog-followup.json'
$packet = Join-Path $dir 'packet-followup.etl'
$state = Join-Path $dir 'netlog-setup.json'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
$appName = 'GAMI Hash.exe'

foreach ($app in @(Get-Process -Name 'GAMI Hash' -ErrorAction SilentlyContinue)) {
    $app.CloseMainWindow() | Out-Null
    if (-not $app.WaitForExit(10000)) {
        Stop-Process -Id $app.Id -Force
        $app.WaitForExit(10000) | Out-Null
    }
}
Start-Sleep -Seconds 2
foreach ($webview in @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" | Where-Object CommandLine -Like '*GAMI Hash.exe*')) {
    Stop-Process -Id $webview.ProcessId -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $netlog) { throw 'A prior NetLog file exists.' }
if (Test-Path -LiteralPath $packet) { throw 'A prior packet file exists.' }

$existing = (Get-ItemProperty -LiteralPath $policy -Name $appName -ErrorAction SilentlyContinue).$appName
if ($existing) { throw 'An existing WebView2 policy value for GAMI Hash would be overwritten.' }

New-Item -Path $policy -Force | Out-Null
$flags = '--log-net-log="' + $netlog + '" --net-log-capture-mode=IncludeSensitive'
New-ItemProperty -LiteralPath $policy -Name $appName -Value $flags -PropertyType String -Force | Out-Null
& pktmon.exe filter remove | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not reset pktmon filters.' }
& pktmon.exe start --capture --comp nics --pkt-size 128 --file-name $packet --file-size 128 --log-mode circular | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon start failed.' }

[pscustomobject]@{
    StartedUTC = [DateTime]::UtcNow.ToString('o')
    HostApp = $appName
    BrowserArguments = $flags
    NetLogPath = $netlog
    PacketPath = $packet
    SysmonRunning = [bool](Get-Service Sysmon64 -ErrorAction SilentlyContinue | Where-Object Status -eq Running)
} | ConvertTo-Json | Set-Content -LiteralPath $state -Encoding UTF8
