$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$install = 'C:\Users\tech\AppData\Local\Programs\Authentic Memory Hashing Tool'
$uninstall = Join-Path $install 'uninstall.exe'
if (-not (Test-Path -LiteralPath $uninstall)) { throw 'GAMI uninstaller missing.' }
$process = Start-Process -FilePath $uninstall -ArgumentList '/S' -PassThru
if (-not $process.WaitForExit(60000)) { throw 'GAMI uninstaller did not finish.' }
Start-Sleep -Seconds 2
[pscustomobject]@{
    UninstallUTC = [DateTime]::UtcNow.ToString('o')
    ExitCode = $process.ExitCode
    GuiStillInstalled = Test-Path -LiteralPath (Join-Path $install 'GAMI Hash.exe')
    CliStillInstalled = Test-Path -LiteralPath (Join-Path $install 'gami-hash.exe')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'prepare-missing-runtime.json') -Encoding UTF8
