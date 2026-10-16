$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$version = '155.0.4283.60'
$setup = "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\$version\Installer\setup.exe"
$reg = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
if (-not (Test-Path -LiteralPath $setup)) { throw 'Signed WebView2 runtime setup.exe missing.' }
if ((Get-AuthenticodeSignature -LiteralPath $setup).Status -ne 'Valid') { throw 'WebView2 setup signature invalid.' }
Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$process = Start-Process -FilePath $setup -ArgumentList '--uninstall --msedgewebview --system-level --force-uninstall' -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) { throw 'WebView2 removal exceeded 120 seconds.' }
Start-Sleep -Seconds 5
[pscustomobject]@{
    CheckedUTC = [DateTime]::UtcNow.ToString('o')
    SetupExitCode = $process.ExitCode
    RegisteredVersion = (Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue).pv
    RuntimeExeExists = Test-Path -LiteralPath "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\$version\msedgewebview2.exe"
    RuntimeProcessCount = @(Get-Process msedgewebview2 -ErrorAction SilentlyContinue).Count
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'webview-removal.json') -Encoding UTF8
