param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/verify-windows-signatures.ps1" -Stage Payload
& "$PSScriptRoot/build-windows-installer.ps1" -Version $Version -PackageOnly
