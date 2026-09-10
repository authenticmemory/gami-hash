param(
  [string]$OutputDir = "build/release-metadata"
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
$out = Join-Path $project $OutputDir

New-Item -ItemType Directory -Force $out | Out-Null

Push-Location $project
try {
  go list -m -json all | Set-Content -Encoding utf8 (Join-Path $out "go-modules.json")
  Copy-Item -Force "go.mod" (Join-Path $out "go.mod")
  Copy-Item -Force "go.sum" (Join-Path $out "go.sum")
} finally {
  Pop-Location
}

Push-Location (Join-Path $project "frontend")
try {
  npm ls --json --all | Set-Content -Encoding utf8 (Join-Path $out "npm-tree.json")
  Copy-Item -Force "package.json" (Join-Path $out "frontend-package.json")
  Copy-Item -Force "package-lock.json" (Join-Path $out "frontend-package-lock.json")
} finally {
  Pop-Location
}

Get-ChildItem $out | Select-Object FullName, Length, LastWriteTime
