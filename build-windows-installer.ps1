param([string]$Version = '0.1.0', [switch]$FrameworkDependent, [switch]$PackageOnly)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^(?:test-)?v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid version.' }
$numeric = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$windowsVersion = "$numeric.0"
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
  $ldflags = "-s -w -buildid= -X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version"
  & $go build -trimpath -buildvcs=false -ldflags $ldflags -o (Join-Path $payload 'GamiHashEngine.exe') $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Go worker build failed.' }
}
foreach ($name in @('GamiHash.exe','GamiHashEngine.exe')) {
  if (-not (Test-Path -LiteralPath (Join-Path $payload $name))) { throw "Missing payload: $name" }
}
Push-Location (Join-Path $PSScriptRoot 'packaging/windows-native')
try { & $makensis "/DPRODUCT_VERSION=$windowsVersion" "/DPAYLOAD_DIR=$payload" "/DOUTPUT_FILE=$installer" 'installer.nsi' } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $installer)) { throw 'NSIS build failed.' }
foreach ($file in @((Join-Path $payload 'GamiHash.exe'),(Join-Path $payload 'GamiHashEngine.exe'),$installer)) {
  [pscustomobject]@{ Path=$file; Bytes=(Get-Item $file).Length; SHA256=(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() }
}

