param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Version,
    [string]$OutputDirectory = '',
    [string]$MakeNSIS = 'makensis.exe'
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw 'Version must have four numeric parts and end in .0.' }
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$signature = Get-AuthenticodeSignature -LiteralPath $packagePath
if ($signature.Status -ne 'Valid') { throw "The embedded MSIX signature is not valid: $($signature.StatusMessage)" }
$expectedPackageName = "gami-hash-windows-$Version-x64.msix"
if ([IO.Path]::GetFileName($packagePath) -ne $expectedPackageName) {
    throw "Expected package name $expectedPackageName"
}

if (-not $OutputDirectory) { $OutputDirectory = Split-Path -Parent $packagePath }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = [IO.Path]::GetFullPath((Join-Path $OutputDirectory "gami-hash-windows-$Version-x64-installer.exe"))
$makeNSISCommand = Get-Command $MakeNSIS -ErrorAction Stop
$script = Join-Path $PSScriptRoot 'installer.nsi'

& $makeNSISCommand.Source /V2 `
    "/DPACKAGE_PATH=$packagePath" `
    "/DOUTPUT_PATH=$outputPath" `
    "/DPRODUCT_VERSION=$Version" `
    $script
if ($LASTEXITCODE -ne 0) { throw 'NSIS bootstrapper build failed.' }

[ordered]@{
    product = 'windows-appcontainer-bootstrapper'
    version = $Version
    installer = $outputPath
    sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    embeddedPackage = $expectedPackageName
    embeddedPackageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    installerSigned = (Get-AuthenticodeSignature -LiteralPath $outputPath).Status -eq 'Valid'
} | ConvertTo-Json -Depth 3
