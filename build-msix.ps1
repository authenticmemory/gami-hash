param(
  [string]$Version = '1.0.0.0',
  [string]$IdentityName = 'AuthenticMemory.GAMIHash.Prototype',
  [string]$Publisher = 'CN=GAMI Hash MSIX Prototype',
  [string]$DisplayName = 'GAMI Hash Prototype',
  [string]$PublisherDisplayName = 'Authentic Memory',
  [string]$Alias = 'gami-hash-prototype.exe',
  [string]$Go = 'go',
  [string]$Wails = 'wails',
  [string]$MakeAppx = ''
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.0$') {
  throw 'Use a four-part numeric version with final component 0, e.g. 1.0.0.0. The Store reserves the final component.'
}
foreach ($component in $Version.Split('.')) {
  if ([long]$component -gt 65535) { throw 'Version components must not exceed 65535.' }
}
if ($IdentityName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') { throw 'Invalid MSIX identity name.' }
if ($Alias -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.exe$') { throw 'Alias must be a plain .exe filename.' }
if (-not $Publisher.StartsWith('CN=')) { throw 'Publisher must be the exact Partner Center distinguished name (or the prototype CN).' }
if (-not $MakeAppx) {
  $sdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
  $tool = Get-ChildItem -LiteralPath $sdkBin -Directory |
    Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/makeappx.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (-not $tool) { throw 'Install Windows SDK MSIX packaging tools or pass -MakeAppx.' }
  $MakeAppx = $tool
}
$goCompiler = (Get-Command $Go -ErrorAction Stop).Source
$wailsCompiler = (Get-Command $Wails -ErrorAction Stop).Source
$project = $PSScriptRoot
# Unique staging prevents stale files and avoids deleting prior release artifacts.
$out = Join-Path $project ("build/bin/msix-prototype/{0}-{1}" -f $Version, [guid]::NewGuid().ToString('N'))
$stage = Join-Path $out 'package'
$assets = Join-Path $stage 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
$configPath = Join-Path $project 'wails.json'
$originalConfig = [IO.File]::ReadAllBytes($configPath)
$oldPath = $env:PATH
$env:PATH = "$(Split-Path $goCompiler);$env:PATH"
Push-Location $project
try {
  Push-Location frontend
  try {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency install failed.' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' }
  } finally { Pop-Location }
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $config.info.productVersion = ($Version.Split('.')[0..2] -join '.')
  [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $flags = "-w -s -buildid= -X github.com/authenticmemory/gami-hash/internal/engine.Version=msix-$Version"
  # Use a separate filename; leave the direct-download executable and installer intact.
  & $wailsCompiler build -platform windows/amd64 -compiler $goCompiler -m -nosyncgomod -s -skipbindings -webview2 error -trimpath -tags 'desktop,production' -ldflags $flags -o gami-hash-msix.exe
  if ($LASTEXITCODE -ne 0) { throw 'MSIX GUI build failed.' }
  Copy-Item -LiteralPath 'build/bin/gami-hash-msix.exe' -Destination (Join-Path $stage 'GAMI Hash.exe')
  & $goCompiler build -trimpath -buildvcs=false -tags cli -ldflags $flags -o (Join-Path $stage 'gami-hash-cli.exe') .
  if ($LASTEXITCODE -ne 0) { throw 'MSIX CLI build failed.' }

  [xml]$manifest = Get-Content -LiteralPath 'packaging/msix/AppxManifest.xml' -Raw
  $manifest.Package.Identity.SetAttribute('Name', $IdentityName)
  $manifest.Package.Identity.SetAttribute('Publisher', $Publisher)
  $manifest.Package.Identity.SetAttribute('Version', $Version)
  $manifest.Package.Properties.DisplayName = $DisplayName
  $manifest.Package.Properties.PublisherDisplayName = $PublisherDisplayName
  $ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
  $ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
  $ns.AddNamespace('uap5', 'http://schemas.microsoft.com/appx/manifest/uap/windows10/5')
  $manifest.SelectSingleNode('//uap:VisualElements', $ns).SetAttribute('DisplayName', $DisplayName)
  $manifest.SelectSingleNode('//uap5:ExecutionAlias', $ns).SetAttribute('Alias', $Alias)
  $manifest.Save((Join-Path $stage 'AppxManifest.xml'))
  Copy-Item -LiteralPath LICENSE -Destination $stage

  Add-Type -AssemblyName System.Drawing
  $source = [Drawing.Image]::FromFile((Join-Path $project 'build/appicon.png'))
  try {
    foreach ($asset in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150))) {
      $size = [int]$asset[1]
      $bitmap = New-Object Drawing.Bitmap($size, $size)
      $graphics = [Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $scale = [Math]::Min($size / $source.Width, $size / $source.Height)
        $width = [int]($source.Width * $scale); $height = [int]($source.Height * $scale)
        $graphics.DrawImage($source, [int](($size-$width)/2), [int](($size-$height)/2), $width, $height)
        $bitmap.Save((Join-Path $assets ($asset[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
      } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
  } finally { $source.Dispose() }
  $package = Join-Path $out ("gami-hash-$Version-x64.msix")
  & $MakeAppx pack /d $stage /p $package /o
  if ($LASTEXITCODE -ne 0) { throw 'MakeAppx schema/content validation or packaging failed.' }
  & $MakeAppx unpack /p $package /d (Join-Path $out 'unpacked-check') /o
  if ($LASTEXITCODE -ne 0) { throw 'MSIX unpack verification failed.' }
  foreach ($file in @('GAMI Hash.exe', 'gami-hash-cli.exe', 'AppxManifest.xml')) {
    if ((Get-FileHash (Join-Path $stage $file)).Hash -ne (Get-FileHash (Join-Path $out "unpacked-check/$file")).Hash) {
      throw "Packaged payload differs: $file"
    }
  }
  $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $(Split-Path $package -Leaf)" | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding ascii
  @{
    identity = $IdentityName; publisher = $Publisher; version = $Version; alias = $Alias
    architecture = 'x64'; signed = $false; installedTested = $false
    webview2 = 'Requires preinstalled Evergreen runtime; no runtime bundled'
    sourceCommit = ((git rev-parse HEAD) -join ''); go = ((& $goCompiler version) -join '')
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'build-report.json') -Encoding utf8
  Write-Output "Unsigned prototype: $package"
  Write-Output 'MakeAppx validation and payload round-trip passed. Installation, upgrade and GUI acceptance are still required.'
} finally {
  [IO.File]::WriteAllBytes($configPath, $originalConfig)
  $env:PATH = $oldPath
  Pop-Location
}
