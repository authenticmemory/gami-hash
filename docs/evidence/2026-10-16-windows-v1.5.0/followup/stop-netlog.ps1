$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
foreach ($app in @(Get-Process -Name 'GAMI Hash' -ErrorAction SilentlyContinue)) {
    $app.CloseMainWindow() | Out-Null
    if (-not $app.WaitForExit(10000)) {
        Stop-Process -Id $app.Id -Force
        $app.WaitForExit(10000) | Out-Null
    }
}
Start-Sleep -Seconds 4
& pktmon.exe stop | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pktmon stop failed.' }
& wevtutil.exe epl 'Microsoft-Windows-Sysmon/Operational' (Join-Path $dir 'sysmon-followup.evtx')
if ($LASTEXITCODE -ne 0) { throw 'Sysmon export failed.' }
Remove-ItemProperty -LiteralPath $policy -Name 'GAMI Hash.exe' -ErrorAction Stop
$paths = @('netlog-followup.json','packet-followup.etl','sysmon-followup.evtx')
[pscustomobject]@{
    StoppedUTC = [DateTime]::UtcNow.ToString('o')
    Files = @($paths | ForEach-Object {
        $path = Join-Path $dir $_
        [pscustomobject]@{
            Name = $_
            Exists = Test-Path -LiteralPath $path
            Bytes = if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).Length } else { 0 }
            SHA256 = if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } else { $null }
        }
    })
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'netlog-stop.json') -Encoding UTF8
