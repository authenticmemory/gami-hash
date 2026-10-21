param([string]$Version = '0.1.0', [switch]$FrameworkDependent, [switch]$PackageOnly)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^(?:test-)?v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid version.' }
$numeric = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$windowsVersion = "$numeric.0"
$versionParts = $numeric.Split('.')
$installDate = Get-Date -Format 'yyyyMMdd'
foreach ($part in $numeric.Split('.')) { if ([long]$part -gt 65535) { throw 'Version component exceeds 65535.' } }
$project = Join-Path $PSScriptRoot 'windows/GamiHash.Windows/GamiHash.Windows.csproj'
$payload = Join-Path $PSScriptRoot 'build/windows-native/payload'
$dist = Join-Path $PSScriptRoot 'build/bin'
$installer = Join-Path $dist "gami-hash-windows-$numeric-x64-installer.exe"
$go = if (Get-Command go -ErrorAction SilentlyContinue) { (Get-Command go).Source } else { 'C:\Program Files\Go\bin\go.exe' }
$makensis = if (Get-Command makensis -ErrorAction SilentlyContinue) { (Get-Command makensis).Source } else { 'C:\Program Files (x86)\NSIS\makensis.exe' }
if (-not (Test-Path -LiteralPath $go)) { throw 'Go is not installed.' }
if (-not (Test-Path -LiteralPath $makensis)) { throw 'NSIS is not installed.' }
New-Item -ItemType Directory -Force $payload,$dist | Out-Null
if (-not $PackageOnly) {
  $publish = @('publish',$project,'-c','Release','-r','win-x64','-o',$payload,"/p:Version=$numeric","/p:FileVersion=$windowsVersion","/p:AssemblyVersion=$windowsVersion",'/p:PublishSingleFile=true','/p:IncludeNativeLibrariesForSelfExtract=true','/p:DebugType=None')
  if (-not $FrameworkDependent) { $publish += @('--self-contained','true') }
  & dotnet @publish
  if ($LASTEXITCODE -ne 0) { throw 'WPF publish failed.' }
  # Candidate tags identify CI runs; the installed product reports the public
  # semantic version that will be promoted byte-for-byte.
  $ldflags = "-s -w -buildid= -X github.com/authenticmemory/gami-hash/internal/engine.Version=v$numeric"
  # The worker also supplies the optional gami-hash.exe CLI. The cli build tag
  # keeps its no-argument path in console mode instead of invoking retired Wails.
  & $go build -tags cli -trimpath -buildvcs=false -ldflags $ldflags -o (Join-Path $payload 'GamiHashEngine.exe') $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Go worker build failed.' }

  $uninstaller = Join-Path $payload 'Uninstall.exe'
  $generator = Join-Path $PSScriptRoot 'packaging/windows-native/uninstaller-generator.exe'
  $generatedUninstaller = Join-Path $PSScriptRoot 'packaging/windows-native/Uninstall.exe'
  Push-Location (Join-Path $PSScriptRoot 'packaging/windows-native')
  try {
    Remove-Item -LiteralPath $generatedUninstaller -Force -ErrorAction SilentlyContinue
    & $makensis 'uninstaller-generator.nsi'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $generator)) { throw 'Uninstaller generator build failed.' }
    $generatorProcess = Start-Process -FilePath $generator -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
    if ($generatorProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $generatedUninstaller)) { throw 'Uninstaller generation failed.' }
    Move-Item -LiteralPath $generatedUninstaller -Destination $uninstaller -Force
  } finally {
    Remove-Item -LiteralPath $generator -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $generatedUninstaller -Force -ErrorAction SilentlyContinue
    Pop-Location
  }
}
foreach ($name in @('GamiHash.exe','GamiHashEngine.exe','Uninstall.exe')) {
  if (-not (Test-Path -LiteralPath (Join-Path $payload $name))) { throw "Missing payload: $name" }
}
$payloadBytes = (Get-ChildItem -LiteralPath $payload -File | Measure-Object -Property Length -Sum).Sum
$cliBytes = (Get-Item -LiteralPath (Join-Path $payload 'GamiHashEngine.exe')).Length
$installedSizeKB = [math]::Ceiling(($payloadBytes + $cliBytes) / 1KB)
Push-Location (Join-Path $PSScriptRoot 'packaging/windows-native')
try { & $makensis "/DPRODUCT_VERSION=$windowsVersion" "/DVERSION_MAJOR=$($versionParts[0])" "/DVERSION_MINOR=$($versionParts[1])" "/DINSTALL_DATE=$installDate" "/DINSTALLED_SIZE_KB=$installedSizeKB" "/DPAYLOAD_DIR=$payload" "/DOUTPUT_FILE=$installer" 'installer.nsi' } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $installer)) { throw 'NSIS build failed.' }
$guiVersion = (Get-Item -LiteralPath (Join-Path $payload 'GamiHash.exe')).VersionInfo
if ($guiVersion.ProductName -ne 'Authentic Memory Hashing Tool') { throw "Incorrect GUI product metadata: $($guiVersion.ProductName)" }
$installerVersion = (Get-Item -LiteralPath $installer).VersionInfo
if ($installerVersion.ProductName -ne 'Authentic Memory Hashing Tool') { throw "Incorrect installer product metadata: $($installerVersion.ProductName)" }
foreach ($file in @((Join-Path $payload 'GamiHash.exe'),(Join-Path $payload 'GamiHashEngine.exe'),$installer)) {
  [pscustomobject]@{ Path=$file; Bytes=(Get-Item $file).Length; SHA256=(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() }
}

