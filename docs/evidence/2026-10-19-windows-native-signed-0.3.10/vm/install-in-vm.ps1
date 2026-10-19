$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$identity = Get-Content -Raw -LiteralPath (Join-Path $root 'artifact-identity.json') | ConvertFrom-Json
$installer = Join-Path $root $identity.installer
$expected = $identity.sha256
$actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Installer hash mismatch: $actual" }
$process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
$app = "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash\GamiHash.exe"
$worker = "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash\GamiHashEngine.exe"
if (-not (Test-Path -LiteralPath $app) -or -not (Test-Path -LiteralPath $worker)) { throw 'Installed payload is incomplete.' }
[ordered]@{
  installerSha256=$actual
  app=$app
  appSha256=(Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash.ToLowerInvariant()
  workerSha256=(Get-FileHash -LiteralPath $worker -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'install-verification.json') -Encoding UTF8
