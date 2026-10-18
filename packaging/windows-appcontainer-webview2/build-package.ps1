param(
    [string]$Version = '1.6.0.0',
    [string]$Go = 'go',
    [string]$Publisher = 'CN=GAMI Hash Windows Development',
    [string]$DevCertificateThumbprint = '',
    [switch]$Release,
    [switch]$SkipFrontendBuild
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw 'Version must have four numeric parts and end in .0.' }
if ($Release -and $DevCertificateThumbprint) { throw 'Release packages must be signed by the release pipeline, not a development certificate.' }
if ($Release -and $Publisher -eq 'CN=GAMI Hash Windows Development') { throw 'Release packages require the organization signing publisher.' }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sdk = '10.0.22621.0'
$makeAppx = "C:\Program Files (x86)\Windows Kits\10\bin\$sdk\x64\makeappx.exe"
$signTool = "C:\Program Files (x86)\Windows Kits\10\bin\$sdk\x64\signtool.exe"
$out = Join-Path $repo "build/bin/windows-appcontainer-webview2/$Version"
$stage = Join-Path $out 'stage'
$assets = Join-Path $stage 'Assets'

if (-not (Test-Path -LiteralPath $makeAppx)) { throw "MakeAppx not found: $makeAppx" }
$goCommand = Get-Command $Go -ErrorAction Stop

if ($SkipFrontendBuild) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'frontend/dist/index.html'))) {
        throw 'SkipFrontendBuild requires an existing frontend/dist build.'
    }
} else {
    Push-Location (Join-Path $repo 'frontend')
    try {
        npm ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
        npm run build
        if ($LASTEXITCODE -ne 0) { throw 'frontend build failed' }
    } finally { Pop-Location }
}

New-Item -ItemType Directory -Force -Path $assets | Out-Null
$exe = Join-Path $stage 'GamiHash.exe'
$ldflags = "-w -s -buildid= -H windowsgui -X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version"
Push-Location $repo
try {
    & $goCommand.Source build -trimpath -buildvcs=false -tags 'desktop,production,windows_appcontainer' -ldflags $ldflags -o $exe .
    if ($LASTEXITCODE -ne 0) { throw 'Windows AppContainer executable build failed' }
} finally { Pop-Location }

# Slice 3 reuses the product broker unchanged behind a narrow C ABI DLL. The
# DLL retains WinRT StorageFolder grants; the Go/WebView layer sees display
# strings only and never turns those strings back into filesystem authority.
$components = Join-Path $repo 'build/bin/windows-appcontainer-webview2-components'
& (Join-Path $repo 'packaging/windows-appcontainer/build-product-components.ps1') `
    -OutputDirectory $components -Version $Version | Out-Null
$vc = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$cppwinrt = "C:\Program Files (x86)\Windows Kits\10\Include\$sdk\cppwinrt"
$bridge = Join-Path $stage 'GamiHashStorageBridge.dll'
$bridgeBuild = 'call "' + $vc + '" >nul && cl /nologo /std:c++20 /EHsc /MD /LD /DUNICODE /D_UNICODE /I "' + `
    $cppwinrt + '" /I "' + (Join-Path $repo 'packaging/windows-appcontainer') + '" "' + `
    (Join-Path $PSScriptRoot 'storage_bridge.cpp') + '" "' + (Join-Path $components 'GamiHashStorageBroker.lib') + `
    '" /Fe:"' + $bridge + '" /link windowsapp.lib onecore.lib ole32.lib shell32.lib'
& cmd.exe /d /s /c $bridgeBuild
if ($LASTEXITCODE -ne 0) { throw 'Storage bridge DLL build failed' }
Copy-Item -LiteralPath (Join-Path $components 'GamiHashContainedWorker.exe') -Destination $stage -Force

[xml]$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
$manifest.Package.Identity.Version = $Version
$manifest.Package.Identity.Publisher = $Publisher
$manifest.Save((Join-Path $stage 'AppxManifest.xml'))

Add-Type -AssemblyName System.Drawing
$source = [Drawing.Image]::FromFile((Join-Path $repo 'build/appicon.png'))
try {
    foreach ($asset in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150))) {
        $size = [int]$asset[1]
        $bitmap = New-Object Drawing.Bitmap($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.DrawImage($source, 0, 0, $size, $size)
            $bitmap.Save((Join-Path $assets ($asset[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $source.Dispose() }

$package = Join-Path $out "gami-hash-windows-$Version-x64.msix"
& $makeAppx pack /d $stage /p $package /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed' }

$unpacked = Join-Path $out 'unpacked-check'
$resolvedOut = [IO.Path]::GetFullPath($out).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$resolvedUnpacked = [IO.Path]::GetFullPath($unpacked)
if (-not $resolvedUnpacked.StartsWith($resolvedOut, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe unpack verification path: $resolvedUnpacked"
}
if (Test-Path -LiteralPath $resolvedUnpacked) { Remove-Item -LiteralPath $resolvedUnpacked -Recurse -Force }
& $makeAppx unpack /p $package /d $unpacked /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'MSIX unpack verification failed' }
foreach ($relativePath in @('AppxManifest.xml', 'GamiHash.exe', 'GamiHashStorageBridge.dll', 'GamiHashContainedWorker.exe')) {
    $stagedHash = (Get-FileHash -LiteralPath (Join-Path $stage $relativePath) -Algorithm SHA256).Hash
    $packedHash = (Get-FileHash -LiteralPath (Join-Path $unpacked $relativePath) -Algorithm SHA256).Hash
    if ($stagedHash -ne $packedHash) { throw "Packaged payload differs from staging: $relativePath" }
}

if ($DevCertificateThumbprint) {
    if (-not (Test-Path -LiteralPath $signTool)) { throw "SignTool not found: $signTool" }
    $certificate = Get-Item -LiteralPath ("Cert:\CurrentUser\My\" + $DevCertificateThumbprint)
    if ($certificate.Subject -ne $Publisher -or -not $certificate.HasPrivateKey) {
        throw 'The signing certificate subject/private key does not match the package publisher.'
    }
    & $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint $package | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed' }
    Export-Certificate -Cert $certificate -FilePath (Join-Path $out 'development-certificate.cer') -Force | Out-Null

    $installer = @"
param([string]`$Directory = `$PSScriptRoot)
`$ErrorActionPreference = 'Stop'
`$certificate = Join-Path `$Directory 'development-certificate.cer'
`$package = Join-Path `$Directory 'gami-hash-windows-$Version-x64.msix'
if (-not (Test-Path -LiteralPath `$certificate) -or -not (Test-Path -LiteralPath `$package)) {
    throw 'Keep the certificate, MSIX, and installer together in one directory.'
}
`$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an elevated PowerShell. The development certificate must be trusted in LocalMachine\TrustedPeople.'
}
Import-Certificate -FilePath `$certificate -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
Add-AppxPackage -Path `$package -ForceApplicationShutdown
Get-AppxPackage -Name AuthenticMemory.GAMIHash.Windows |
    Select-Object Name, PackageFullName, PackageFamilyName, InstallLocation
"@
    Set-Content -LiteralPath (Join-Path $out 'install-in-vm.ps1') -Value $installer -Encoding UTF8
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'inspect-process-tree.ps1') -Destination $out -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'collect-sysmon-processes.ps1') -Destination $out -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $out 'RUNBOOK.md') -Force

$manifestText = Get-Content -LiteralPath (Join-Path $stage 'AppxManifest.xml') -Raw
if ($manifestText -match 'runFullTrust|internetClient|internetClientServer|privateNetworkClientServer') {
    throw 'Forbidden capability found in staged manifest.'
}

$report = [ordered]@{
    prototype = $false
    release = [bool]$Release
    product = 'windows-appcontainer-webview2'
    version = $Version
    package = $package
    sha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    signed = [bool]$DevCertificateThumbprint
    runtimeTested = $false
    payloadRoundTripVerified = $true
    certificateSubject = if ($DevCertificateThumbprint) { $certificate.Subject } else { $null }
    certificateThumbprint = if ($DevCertificateThumbprint) { $certificate.Thumbprint } else { $null }
    frontend = 'embedded frontend/dist'
    trustLevel = 'appContainer'
    capabilities = @()
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'build-report.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 4
