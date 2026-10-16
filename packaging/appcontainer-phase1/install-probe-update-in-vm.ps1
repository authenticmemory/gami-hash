param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$package = Join-Path $Directory 'gami-phase1-probe-0.1.1.0-x64.msix'
$certificate = Join-Path $Directory 'development-certificate-0.1.1.0.cer'
$resultFile = Join-Path $Directory 'install-update-result.json'
$result = [ordered]@{
    timestampUtc = [DateTime]::UtcNow.ToString('o')
    user = [Environment]::UserName
    packageSHA256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    certificateSHA256 = (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
}
try {
    Import-Certificate -FilePath $certificate -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
    Get-Process GamiPhase1Probe -ErrorAction SilentlyContinue | Stop-Process -Force
    Add-AppxPackage -Path $package -ErrorAction Stop
    $installed = Get-AppxPackage -Name AuthenticMemory.GAMIHash.AppContainerProbe
    if (-not $installed -or $installed.Version.ToString() -ne '0.1.1.0') {
        throw 'Updated probe package was not found for this account.'
    }
    $result.status = 'installed'
    $result.packageFullName = $installed.PackageFullName
} catch {
    $result.status = 'failed'
    $result.error = $_.Exception.Message
}
$result | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding UTF8
if ($result.status -ne 'installed') { exit 1 }
