param([Parameter(Mandatory)][string]$Package)

$ErrorActionPreference = 'Stop'
Add-AppxPackage -LiteralPath $Package -ForceApplicationShutdown -ErrorAction Stop
