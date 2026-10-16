$p = 'C:\Users\Public\Documents\GamiHashTest\proxy-control.json'
try {
    $r = Invoke-WebRequest -Uri 'https://example.com/' -Proxy 'http://192.168.247.1:8766' -UseBasicParsing -TimeoutSec 15
    @{ Status = $r.StatusCode; TimeUTC = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $p
} catch {
    @{ Error = $_.Exception.Message; TimeUTC = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $p
}
