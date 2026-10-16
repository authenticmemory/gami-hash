$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$proxy = '192.168.247.1:8766'
$cert = Join-Path $dir 'mitmproxy-ca-cert.cer'
$state = Join-Path $dir 'proxy-state.json'
if (Test-Path -LiteralPath $state) { throw 'A prior proxy state file exists.' }

foreach ($app in @(Get-Process -Name 'GAMI Hash' -ErrorAction SilentlyContinue)) {
    $app.CloseMainWindow() | Out-Null
    if (-not $app.WaitForExit(10000)) { Stop-Process -Id $app.Id -Force }
}
Start-Sleep -Seconds 2

$tech = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True AND Name='tech'"
if (-not $tech -or @($tech).Count -ne 1) { throw 'Could not uniquely identify local tech account.' }
$key = "Registry::HKEY_USERS\$($tech.SID)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
if (-not (Test-Path -LiteralPath $key)) { throw 'tech user registry hive is not loaded.' }
$old = Get-ItemProperty -LiteralPath $key
$certObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
$thumbprint = $certObject.Thumbprint
if (Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $thumbprint) { throw 'Proxy CA already trusted.' }

$result = [pscustomobject]@{
    StartedUTC = [DateTime]::UtcNow.ToString('o')
    UserSID = $tech.SID
    ProxyKey = $key
    OldProxyEnable = $old.ProxyEnable
    OldProxyServer = $old.ProxyServer
    OldProxyOverride = $old.ProxyOverride
    AddedCertThumbprint = $thumbprint
    NewProxyServer = $proxy
}
$result | ConvertTo-Json | Set-Content -LiteralPath $state -Encoding UTF8
Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Set-ItemProperty -LiteralPath $key -Name ProxyEnable -Type DWord -Value 1
Set-ItemProperty -LiteralPath $key -Name ProxyServer -Type String -Value $proxy
Set-ItemProperty -LiteralPath $key -Name ProxyOverride -Type String -Value '<local>'

& pktmon.exe filter remove | Out-Null
& pktmon.exe start --capture --comp nics --pkt-size 256 --file-name (Join-Path $dir 'packet-proxy.etl') --file-size 128 --log-mode circular | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon start failed.' }
