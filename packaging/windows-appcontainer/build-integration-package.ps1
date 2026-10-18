param(
    [string]$Version = '0.2.0.0',
    [string]$DevCertificateThumbprint = '',
    [switch]$Sign,
    [switch]$SkipProductBuild
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw 'Invalid MSIX version' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$product = Join-Path $repo 'build/bin/windows-appcontainer-product'
if (-not $SkipProductBuild) {
  & (Join-Path $PSScriptRoot 'build-product-components.ps1') -OutputDirectory $product -Version $Version | Out-Null
} elseif (-not (Test-Path (Join-Path $product 'GamiHashStorageBroker.lib')) -or
          -not (Test-Path (Join-Path $product 'GamiHashContainedWorker.exe'))) {
  throw 'SkipProductBuild requires existing product broker and worker binaries'
}
$sdk='10.0.22621.0'; $vc='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$cppwinrt="C:\Program Files (x86)\Windows Kits\10\Include\$sdk\cppwinrt"
$makeappx="C:\Program Files (x86)\Windows Kits\10\bin\$sdk\x64\makeappx.exe"
$signtool="C:\Program Files (x86)\Windows Kits\10\bin\$sdk\x64\signtool.exe"
$out=Join-Path $repo "build/bin/windows-appcontainer-product/package-$Version"
$stage=Join-Path $out 'stage'; $assets=Join-Path $stage 'Assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$fonts=Join-Path $assets 'Fonts'
New-Item -ItemType Directory -Force -Path $fonts | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'assets/fonts/*') $fonts -Force
$hostExe=Join-Path $stage 'GamiHash.exe'
$resource=Join-Path $out 'integration_host.res'
$compile='call "'+$vc+'" >nul && rc /nologo /fo "'+$resource+'" "'+(Join-Path $PSScriptRoot 'integration_host.rc')+'" && cl /nologo /std:c++20 /utf-8 /EHsc /MD /DUNICODE /D_UNICODE /I "'+$cppwinrt+'" /I "'+$PSScriptRoot+'" "'+(Join-Path $PSScriptRoot 'integration_host.cpp')+'" "'+(Join-Path $product 'GamiHashStorageBroker.lib')+'" "'+$resource+'" /Fe:"'+$hostExe+'" /link /SUBSYSTEM:WINDOWS windowsapp.lib onecore.lib user32.lib gdi32.lib dwmapi.lib'
& cmd.exe /d /s /c $compile
if($LASTEXITCODE-ne 0){throw 'Integration host build failed'}
Copy-Item (Join-Path $product 'GamiHashContainedWorker.exe') $stage
[xml]$manifest=Get-Content (Join-Path $PSScriptRoot 'IntegrationHost.AppxManifest.xml') -Raw
$manifest.Package.Identity.Version=$Version; $manifest.Save((Join-Path $stage 'AppxManifest.xml'))
Add-Type -AssemblyName System.Drawing
$icon=[Drawing.Image]::FromFile((Join-Path $repo 'build/appicon.png'))
try { foreach($a in @(@('StoreLogo',50),@('Square44x44Logo',44),@('Square150x150Logo',150))){$b=New-Object Drawing.Bitmap([int]$a[1],[int]$a[1]);$g=[Drawing.Graphics]::FromImage($b);try{$g.DrawImage($icon,0,0,[int]$a[1],[int]$a[1]);$b.Save((Join-Path $assets ($a[0]+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$b.Dispose()}}}finally{$icon.Dispose()}
$package=Join-Path $out "gami-hash-windows-native-$Version-x64.msix"
& $makeappx pack /d $stage /p $package /o | Out-Null
if($LASTEXITCODE-ne 0){throw 'MSIX packaging failed'}
if($DevCertificateThumbprint){
  $cert=Get-Item -LiteralPath ("Cert:\CurrentUser\My\"+$DevCertificateThumbprint)
  if($cert.Subject -notin @('CN=GAMI Hash Phase 1 Probe','CN=GAMI Hash Phase 3 Integration','CN=GAMI Hash Phase 4 Development') -or -not $cert.HasPrivateKey){throw 'Invalid development certificate'}
  & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint $package | Out-Null
  if($LASTEXITCODE-ne 0){throw 'MSIX signing failed'}
  Export-Certificate -Cert $cert -FilePath (Join-Path $out 'development-certificate.cer') -Force | Out-Null
} elseif($Sign) {
  $generated=New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=GAMI Hash Phase 1 Probe' -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -HashAlgorithm SHA256 -KeyLength 3072 -NotAfter (Get-Date).AddDays(30)
  try {
    Export-Certificate -Cert $generated -FilePath (Join-Path $out 'development-certificate.cer') -Force | Out-Null
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try {$signOutput=& $signtool sign /debug /fd SHA256 /sha1 $generated.Thumbprint $package 2>&1;$signExit=$LASTEXITCODE} finally {$ErrorActionPreference=$prior}
    $signOutput | Set-Content (Join-Path $out 'signing-output.txt')
    if($signExit-ne 0){throw 'MSIX signing failed; see signing-output.txt'}
  } finally { Remove-Item -LiteralPath ("Cert:\CurrentUser\My\"+$generated.Thumbprint) -Force }
}
if ($DevCertificateThumbprint -or $Sign) {
  $installer = @"
# Development test installer for GAMI Hash $Version.
# Run this script from an Administrator PowerShell session.
`$ErrorActionPreference = 'Stop'
`$here = Split-Path -Parent `$MyInvocation.MyCommand.Path
Import-Certificate -FilePath (Join-Path `$here 'development-certificate.cer') -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
Add-AppxPackage -Path (Join-Path `$here 'gami-hash-windows-native-$Version-x64.msix') -ForceApplicationShutdown
Write-Output 'GAMI Hash $Version installed successfully.'
"@
  Set-Content -LiteralPath (Join-Path $out 'install-development-package.ps1') -Value $installer -Encoding UTF8
}
$hash=(Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{prototype=$false;release=$false;phase=4;package=$package;sha256=$hash;signed=[bool]($DevCertificateThumbprint -or $Sign);runtimeTested=$false} | ConvertTo-Json | Set-Content (Join-Path $out 'build-report.json')
Write-Output $package; Write-Output $hash
