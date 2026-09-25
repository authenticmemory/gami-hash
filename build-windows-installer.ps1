param(
  [string]$Version = "0.1.0",
  [ValidateSet("user", "machine")]
  [string]$InstallScope = "user",
  [string]$Wails = "wails",
  [string]$Go = "go"
)

$ErrorActionPreference = "Stop"
if ($Version -notmatch '^(?:test-)?v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
  throw "Version must be a numeric release version, such as v1.2.3 or test-v1.2.3."
}
$numericVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
foreach ($part in $numericVersion.Split('.')) {
  if ([long]$part -gt 65535) { throw "Windows version components must be at most 65535." }
}

$project = $PSScriptRoot
$frontend = Join-Path $project "frontend"
$dist = Join-Path $project "build/bin"
$windowsBuild = Join-Path $project "build/windows"
$installerBuild = Join-Path $windowsBuild "installer"

function Resolve-CommandPath([string]$Name, [string[]]$Fallbacks) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($path in $Fallbacks) {
    if (Test-Path -LiteralPath $path) { return $path }
  }
  throw "$Name was not found. Install NSIS or pass a Wails/NSIS environment where $Name is on PATH."
}

$goCompiler = Resolve-CommandPath $Go @(
  "C:\Users\STUDENT\projects\auth-mem\.tools\go1.27.0\go\bin\go.exe",
  "$env:USERPROFILE\go\bin\go.exe"
)
$env:PATH = "$(Split-Path -Parent $goCompiler);$env:PATH"

$makensis = Resolve-CommandPath "makensis" @(
  "C:\Program Files (x86)\NSIS\makensis.exe",
  "C:\Program Files (x86)\NSIS\Bin\makensis.exe",
  "C:\Program Files\NSIS\makensis.exe",
  "C:\Program Files\NSIS\Bin\makensis.exe"
)
$env:PATH = "$(Split-Path -Parent $makensis);$env:PATH"

Push-Location $frontend
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "frontend build failed" }
} finally {
  Pop-Location
}

$configPath = Join-Path $project "wails.json"
$configBytes = [IO.File]::ReadAllBytes($configPath)
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$config.info.productVersion = $numericVersion
Push-Location $project
try {
  [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  New-Item -ItemType Directory -Force $dist | Out-Null
  New-Item -ItemType Directory -Force $installerBuild | Out-Null
  Remove-Item -LiteralPath (Join-Path $windowsBuild "icon.ico") -Force -ErrorAction SilentlyContinue
  $ldflags = "-w -s -buildid= -X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version"
  $cliBinary = Join-Path $installerBuild "gami-hash-cli.exe"
  & $goCompiler build `
    -trimpath `
    -buildvcs=false `
    -tags cli `
    -ldflags $ldflags `
    -o $cliBinary `
    .
  if ($LASTEXITCODE -ne 0) { throw "CLI build failed" }

  & $Wails build `
    -clean `
    -nsis `
    -compiler $goCompiler `
    -installscope $InstallScope `
    -webview2 error `
    -trimpath `
    -tags "desktop,production" `
    -ldflags $ldflags
  if ($LASTEXITCODE -ne 0) { throw "Wails NSIS build failed" }

  $installers = Get-ChildItem $dist -File |
    Where-Object { $_.Name -like "*installer*.exe" -or $_.Name -like "*setup*.exe" }
  if (-not $installers) {
    throw "Wails completed but did not produce an NSIS installer in $dist"
  }

  # Check the actual PE resources, not just the configuration used to build them.
  $versionedFiles = @((Join-Path $dist "gami-hash.exe")) + @($installers.FullName)
  foreach ($file in $versionedFiles) {
    $info = (Get-Item -LiteralPath $file).VersionInfo
    $actualFile = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart)"
    $actualProduct = "$($info.ProductMajorPart).$($info.ProductMinorPart).$($info.ProductBuildPart)"
    if ($actualFile -ne $numericVersion -or $actualProduct -ne $numericVersion) {
      throw "Version metadata mismatch in ${file}: file=$actualFile product=$actualProduct expected=$numericVersion"
    }
  }

  $installers | ForEach-Object {
    Get-Item $_.FullName | Select-Object FullName, Length, LastWriteTime
    Get-FileHash $_.FullName -Algorithm SHA256
  }
} finally {
  [IO.File]::WriteAllBytes($configPath, $configBytes)
  Pop-Location
}
