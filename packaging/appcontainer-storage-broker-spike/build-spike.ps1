param(
  [string]$Version = '0.1.0.0',
  [Parameter(Mandatory)][string]$Publisher
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw 'Use a four-part MSIX version ending in .0' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sdk = '10.0.22621.0'
$vc = @(
  'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat',
  'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$kits = 'C:\Program Files (x86)\Windows Kits\10'
$cppwinrt = Join-Path $kits "Include\$sdk\cppwinrt"
$makeappx = Join-Path $kits "bin\$sdk\x64\makeappx.exe"
foreach ($required in @($vc, $cppwinrt, $makeappx)) {
  if (-not $required -or -not (Test-Path -LiteralPath $required)) { throw "Missing build dependency: $required" }
}

$out = Join-Path $repo "build/bin/appcontainer-storage-broker-spike/$Version"
$stage = Join-Path $out 'stage'
$assets = Join-Path $stage 'Assets'
Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $assets -Force | Out-Null

function Invoke-NativeCompile([string]$Source, [string]$Output, [string]$CompileFlags, [string]$LinkFlags) {
  $command = 'call "' + $vc + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE ' +
    $CompileFlags + ' /I "' + $cppwinrt + '" "' + $Source + '" /Fe:"' + $Output + '" /link /SUBSYSTEM:WINDOWS ' + $LinkFlags
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $Source" }
}

Invoke-NativeCompile (Join-Path $PSScriptRoot 'caller.cpp') `
  (Join-Path $stage 'GamiHashBrokerCaller.exe') '' 'windowsapp.lib onecore.lib user32.lib'
Invoke-NativeCompile (Join-Path $PSScriptRoot 'broker.cpp') `
  (Join-Path $stage 'GamiHashStorageBrokerSpike.exe') '/DWINAPI_FAMILY=WINAPI_FAMILY_APP' '/APPCONTAINER windowsapp.lib'

[xml]$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
$manifest.Package.Identity.Version = $Version
$manifest.Package.Identity.Publisher = $Publisher
$manifest.Save((Join-Path $stage 'AppxManifest.xml'))

Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Image]::FromFile((Join-Path $repo 'build/appicon.png'))
try {
  foreach ($asset in @(@('StoreLogo',50),@('Square44x44Logo',44),@('Square150x150Logo',150))) {
    $bitmap = New-Object Drawing.Bitmap([int]$asset[1],[int]$asset[1])
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([Drawing.Color]::Transparent)
      $graphics.DrawImage($icon,0,0,[int]$asset[1],[int]$asset[1])
      $bitmap.Save((Join-Path $assets ($asset[0] + '.png')),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
  }
} finally { $icon.Dispose() }

$package = Join-Path $out "gami-storage-broker-spike-$Version-x64.msix"
& $makeappx pack /d $stage /p $package /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx validation failed' }
$unpacked = Join-Path $out 'unpacked-check'
& $makeappx unpack /p $package /d $unpacked /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx round-trip failed' }
$rawManifest = Get-Content -LiteralPath (Join-Path $unpacked 'AppxManifest.xml') -Raw
if ($rawManifest -match 'runFullTrust|internetClient|internetClientServer|privateNetworkClientServer') {
  throw 'Forbidden capability found in broker spike manifest'
}
Write-Output $package
