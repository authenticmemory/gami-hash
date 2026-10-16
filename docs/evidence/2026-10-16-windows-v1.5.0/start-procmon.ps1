$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$exe = Join-Path $dir 'Procmon64.exe'
$log = Join-Path $dir 'gami-file-access.pml'
if (Test-Path -LiteralPath $log) { throw 'Procmon backing file already exists.' }
$existing = @(Get-Process Procmon64 -ErrorAction SilentlyContinue)
if ($existing.Count) { throw 'Procmon is already running.' }
$args = '/AcceptEula /BackingFile "{0}" /Quiet /Minimized' -f $log
Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden
Start-Sleep -Seconds 5
$process = @(Get-Process Procmon64 -ErrorAction SilentlyContinue)
if (-not $process.Count -or -not (Test-Path -LiteralPath $log)) { throw 'Procmon did not start recording.' }
[pscustomobject]@{
    StartedUTC = [DateTime]::UtcNow.ToString('o')
    ProcessIds = @($process.Id)
    BackingFile = $log
    InitialBytes = (Get-Item -LiteralPath $log).Length
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'procmon-start.json') -Encoding UTF8
