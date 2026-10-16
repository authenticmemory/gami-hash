$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$id = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$reg = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$id"
$pv = (Get-ItemProperty -LiteralPath $reg -ErrorAction SilentlyContinue).pv
$setup = 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application\155.0.4283.60\Installer\setup.exe'
[pscustomobject]@{
    CheckedUTC = [DateTime]::UtcNow.ToString('o')
    RuntimeVersionInRegistry = $pv
    RuntimeSetupExists = (Test-Path -LiteralPath $setup)
    RuntimeSetupSignature = if (Test-Path -LiteralPath $setup) { [string](Get-AuthenticodeSignature -LiteralPath $setup).Status } else { $null }
    RuntimeProcessCount = @(Get-Process msedgewebview2 -ErrorAction SilentlyContinue).Count
    GamiProcessCount = @(Get-Process 'GAMI Hash' -ErrorAction SilentlyContinue).Count
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'webview-pre-remove.json') -Encoding UTF8
