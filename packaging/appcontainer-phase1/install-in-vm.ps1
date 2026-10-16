param(
    [string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe'
)

$ErrorActionPreference = 'Stop'
$cert = Join-Path $Directory 'development-certificate.cer'
$package = Join-Path $Directory 'gami-phase1-probe-0.1.0.0-x64.msix'
$status = Join-Path $Directory 'install-result.json'
$result = [ordered]@{ timestampUtc = [DateTime]::UtcNow.ToString('o'); user = [Environment]::UserName }
try {
    foreach ($file in @($cert,$package)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing: $file" }
    }
    $result.packageSHA256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.certificateSHA256 = (Get-FileHash -LiteralPath $cert -Algorithm SHA256).Hash.ToLowerInvariant()
    # Trust must be established by the VM administrator in
    # LocalMachine\TrustedPeople before this noninteractive installer runs.
    Add-AppxPackage -Path $package -ErrorAction Stop
    $app = Get-AppxPackage -Name AuthenticMemory.GAMIHash.AppContainerProbe
    if (-not $app) { throw 'Package not found after installation' }
    $result.packageFullName = $app.PackageFullName
    $result.installLocation = $app.InstallLocation
    $result.status = 'installed'
} catch {
    $result.status = 'failed'
    $result.error = $_.Exception.Message
}
$result | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $status -Encoding UTF8
if ($result.status -ne 'installed') { exit 1 }
