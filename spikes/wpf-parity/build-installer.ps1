$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$project = Join-Path $PSScriptRoot 'GamiHash.WpfSpike/GamiHash.WpfSpike.csproj'
$payload = Join-Path $repo 'build/native-installer-payload'
$output = Join-Path $repo 'build/bin/gami-hash-native-test-0.2.0-x64-installer.exe'
$go = if (Get-Command go -ErrorAction SilentlyContinue) { (Get-Command go).Source } else { 'C:\Program Files\Go\bin\go.exe' }
$makensis = if (Get-Command makensis -ErrorAction SilentlyContinue) { (Get-Command makensis).Source } else { 'C:\Program Files (x86)\NSIS\makensis.exe' }

if (-not (Test-Path -LiteralPath $go)) { throw 'Go is not installed.' }
if (-not (Test-Path -LiteralPath $makensis)) { throw 'NSIS is not installed.' }

New-Item -ItemType Directory -Force $payload | Out-Null
dotnet publish $project -c Release -r win-x64 --self-contained true -o $payload `
  /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true /p:DebugType=None
if ($LASTEXITCODE -ne 0) { throw 'WPF self-contained publish failed.' }

& $go build -trimpath -ldflags '-s -w' -o (Join-Path $payload 'GamiHashEngine.exe') $repo
if ($LASTEXITCODE -ne 0) { throw 'Go worker build failed.' }

Push-Location $PSScriptRoot
try { & $makensis 'installer.nsi' } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw 'NSIS installer build failed.' }

$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output $output
Write-Output "SHA256 $hash"
