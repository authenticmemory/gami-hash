param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$packages = @(Get-AppxPackage -Name '*GAMI*' -ErrorAction SilentlyContinue |
    Select-Object Name,Version,InstallLocation)
$processes = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'gami|hash' -or $_.ExecutablePath -match 'gami'
} | Select-Object ProcessId,Name,ExecutablePath)
$programs = @(Get-ChildItem 'C:\Program Files' -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -Match 'gami|authentic' | Select-Object FullName)
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    packages = $packages
    processes = $processes
    programs = $programs
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'go-binary-inspection.json') -Encoding UTF8
