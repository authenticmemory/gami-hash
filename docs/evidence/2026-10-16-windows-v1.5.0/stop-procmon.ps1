$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$exe = Join-Path $dir 'Procmon64.exe'
$ErrorActionPreference = 'Continue'
& $exe /Terminate /Quiet *> (Join-Path $dir 'procmon-stop.log')
$exit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Start-Sleep -Seconds 3
$processes = @(Get-Process Procmon64 -ErrorAction SilentlyContinue)
[pscustomobject]@{
    StoppedUTC = [DateTime]::UtcNow.ToString('o')
    TerminateExitCode = $exit
    RemainingProcesses = $processes.Count
    BackingFiles = @(Get-ChildItem -LiteralPath $dir -Filter 'gami-file-access*.pml' -File |
        Select-Object Name,Length,@{Name='SHA256';Expression={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'procmon-stop.json') -Encoding UTF8
if ($processes.Count) { throw 'Procmon is still running.' }
