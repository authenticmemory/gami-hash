$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$state = Get-Content -LiteralPath (Join-Path $dir 'proxy-state.json') -Raw | ConvertFrom-Json
foreach ($app in @(Get-Process -Name 'GAMI Hash' -ErrorAction SilentlyContinue)) {
    $app.CloseMainWindow() | Out-Null
    if (-not $app.WaitForExit(10000)) { Stop-Process -Id $app.Id -Force }
}
Start-Sleep -Seconds 3
& pktmon.exe stop | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon stop failed.' }

Set-ItemProperty -LiteralPath $state.ProxyKey -Name ProxyEnable -Type DWord -Value $state.OldProxyEnable
foreach ($name in @('ProxyServer', 'ProxyOverride')) {
    $old = $state."Old$name"
    if ($null -eq $old) {
        Remove-ItemProperty -LiteralPath $state.ProxyKey -Name $name -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -LiteralPath $state.ProxyKey -Name $name -Type String -Value $old
    }
}
Remove-Item -LiteralPath ("Cert:\LocalMachine\Root\" + $state.AddedCertThumbprint) -ErrorAction Stop
$certStillPresent = [bool](Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $state.AddedCertThumbprint)
$current = Get-ItemProperty -LiteralPath $state.ProxyKey
[pscustomobject]@{
    StoppedUTC = [DateTime]::UtcNow.ToString('o')
    ProxyEnable = $current.ProxyEnable
    ProxyServer = $current.ProxyServer
    CertificateStillTrusted = $certStillPresent
    PacketBytes = (Get-Item -LiteralPath (Join-Path $dir 'packet-proxy.etl')).Length
    PacketSHA256 = (Get-FileHash -LiteralPath (Join-Path $dir 'packet-proxy.etl') -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'proxy-stop.json') -Encoding UTF8
