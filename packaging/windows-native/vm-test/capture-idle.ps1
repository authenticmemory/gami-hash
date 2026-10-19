$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
& (Join-Path $root 'start-capture.ps1') -Scenario idle
Start-Sleep -Seconds 30
& (Join-Path $root 'stop-capture.ps1') -Scenario idle
