param(
  [string]$Version = "dev",
  [string]$Output = "build/bin/gami-hash.exe"
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
$frontend = Join-Path $project "frontend"
$outputPath = Join-Path $project $Output

Push-Location $frontend
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "frontend build failed" }
} finally {
  Pop-Location
}

New-Item -ItemType Directory -Force (Split-Path $outputPath) | Out-Null
$ldflags = "-w -s -buildid= -H windowsgui -X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version"
go build -trimpath -buildvcs=false -tags "desktop,production" -ldflags $ldflags -o $outputPath .
if ($LASTEXITCODE -ne 0) { throw "Wails production build failed" }

Get-Item $outputPath | Select-Object FullName, Length, LastWriteTime
Get-FileHash $outputPath -Algorithm SHA256
