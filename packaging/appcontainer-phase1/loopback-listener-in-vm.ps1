param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$port = 48521
$stopFile = Join-Path $Directory 'stop-loopback-listener.flag'
$resultFile = Join-Path $Directory 'loopback-listener-result.json'
$startedFile = Join-Path $Directory 'loopback-listener-started.txt'
$received = [System.Collections.Generic.List[object]]::new()
$tcp4 = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
$tcp6 = [Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback, $port)
$udp4 = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, $port))
$udp6 = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::IPv6Loopback, $port))
try {
    $tcp4.Start()
    $tcp6.Start()
    [DateTime]::UtcNow.ToString('o') | Set-Content -LiteralPath $startedFile
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while (-not (Test-Path -LiteralPath $stopFile) -and [DateTime]::UtcNow -lt $deadline) {
        if ($tcp4.Pending()) {
            $client = $tcp4.AcceptTcpClient()
            $received.Add([ordered]@{ protocol = 'TCP4'; utc = [DateTime]::UtcNow.ToString('o'); remote = $client.Client.RemoteEndPoint.ToString() })
            $client.Close()
        }
        if ($tcp6.Pending()) {
            $client = $tcp6.AcceptTcpClient()
            $received.Add([ordered]@{ protocol = 'TCP6'; utc = [DateTime]::UtcNow.ToString('o'); remote = $client.Client.RemoteEndPoint.ToString() })
            $client.Close()
        }
        if ($udp4.Available -gt 0) {
            $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
            $bytes = $udp4.Receive([ref]$remote)
            $received.Add([ordered]@{ protocol = 'UDP4'; utc = [DateTime]::UtcNow.ToString('o'); remote = $remote.ToString(); bytes = $bytes.Length; payloadHex = [BitConverter]::ToString($bytes).Replace('-','') })
        }
        if ($udp6.Available -gt 0) {
            $remote = [Net.IPEndPoint]::new([Net.IPAddress]::IPv6Any, 0)
            $bytes = $udp6.Receive([ref]$remote)
            $received.Add([ordered]@{ protocol = 'UDP6'; utc = [DateTime]::UtcNow.ToString('o'); remote = $remote.ToString(); bytes = $bytes.Length; payloadHex = [BitConverter]::ToString($bytes).Replace('-','') })
        }
        Start-Sleep -Milliseconds 25
    }
} finally {
    $tcp4.Stop()
    $tcp6.Stop()
    $udp4.Dispose()
    $udp6.Dispose()
    [ordered]@{ stoppedUtc = [DateTime]::UtcNow.ToString('o'); received = @($received) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultFile -Encoding UTF8
}
