$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$processes = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'gami|authentic memory|msedgewebview2'
} | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine)
$installPaths = @(
    'C:\Users\tech\AppData\Local\Programs\Authentic Memory Hashing Tool',
    'C:\Users\gami_runner\AppData\Local\Programs\Authentic Memory Hashing Tool'
)
[pscustomobject]@{
    TimeUTC = [DateTime]::UtcNow.ToString('o')
    InstallPaths = @($installPaths | Where-Object { Test-Path -LiteralPath $_ })
    Processes = $processes
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'app-status.json') -Encoding UTF8
