$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Public\Documents\GamiHashNativeTest'
$installer = Join-Path $root 'gami-hash-native-test-0.2.0-x64-installer.exe'
$expected = 'fd92ffe9d996e187b68a710e932b46623cd0267d115463e6f1acac19166602ac'
$actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Installer hash mismatch: $actual" }
$process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
$app = "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash Native Test\GamiHash.WpfSpike.exe"
$worker = "$env:LOCALAPPDATA\Programs\Authentic Memory\GAMI Hash Native Test\GamiHashEngine.exe"
if (-not (Test-Path -LiteralPath $app) -or -not (Test-Path -LiteralPath $worker)) { throw 'Installed payload is incomplete.' }
[ordered]@{
  installerSha256=$actual
  app=$app
  appSha256=(Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash.ToLowerInvariant()
  workerSha256=(Get-FileHash -LiteralPath $worker -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'install-verification.json') -Encoding UTF8
