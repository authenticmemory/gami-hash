$ErrorActionPreference = 'Stop'
& net.exe use R: /delete /y | Out-Null
& cmdkey.exe /delete:192.168.247.1 | Out-Null
Write-Host 'Guest drive mapping and stored test credential removed.'
