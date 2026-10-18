param([Parameter(Mandatory)][string]$Package)

$ErrorActionPreference = 'Stop'
Add-AppxPackage -Path $Package -ForceApplicationShutdown -ErrorAction Stop
