$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Public\Documents\GamiHashNativeTest'
& (Join-Path $root 'start-capture.ps1') -Scenario idle
Start-Sleep -Seconds 30
& (Join-Path $root 'stop-capture.ps1') -Scenario idle
