param([switch]$Publish)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$project = Join-Path $PSScriptRoot 'GamiHash.WpfSpike/GamiHash.WpfSpike.csproj'
$output = Join-Path $repo 'build/bin/wpf-parity-spike'

dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) { throw 'WPF spike build failed' }

if ($Publish) {
  dotnet publish $project -c Release -r win-x64 --self-contained false -o $output
  if ($LASTEXITCODE -ne 0) { throw 'WPF spike publish failed' }
  $go = Get-Command go -ErrorAction SilentlyContinue
  $goExe = if ($go) { $go.Source } elseif (Test-Path -LiteralPath 'C:\Program Files\Go\bin\go.exe') { 'C:\Program Files\Go\bin\go.exe' }
  if ($goExe) {
    & $goExe build -o (Join-Path $output 'GamiHashEngine.exe') $repo
    if ($LASTEXITCODE -ne 0) { throw 'Go backend probe build failed' }
  } else {
    Write-Warning 'Go is not installed locally; visual and picker gates can run, but the backend probe is deferred.'
  }
  Write-Output (Join-Path $output 'GamiHash.WpfSpike.exe')
}
