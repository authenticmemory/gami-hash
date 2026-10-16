param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name AuthenticMemory.GAMIHash.AppContainerProbe
if (-not $package) { throw 'Probe package is not installed for this account' }
$localState = Join-Path $env:LOCALAPPDATA ('Packages\' + $package.PackageFamilyName + '\LocalState')
$statusFile = Join-Path $localState 'probe-status.txt'
$status = if (Test-Path -LiteralPath $statusFile) { [System.IO.File]::ReadAllText($statusFile) } else { $null }
$processes = @(Get-CimInstance Win32_Process -Filter "Name='GamiPhase1Probe.exe'" -ErrorAction SilentlyContinue |
    Select-Object ProcessId,ParentProcessId,CommandLine)
$manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
$result = [ordered]@{
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    packageFullName = $package.PackageFullName
    packageFamilyName = $package.PackageFamilyName
    installLocation = $package.InstallLocation
    manifestSHA256 = if (Test-Path -LiteralPath $manifest) { (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    processes = $processes
    status = $status
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'runtime-result.json') -Encoding UTF8
