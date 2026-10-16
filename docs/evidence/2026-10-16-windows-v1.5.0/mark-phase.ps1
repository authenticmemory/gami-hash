param([Parameter(Mandatory = $true)][string]$Phase)
$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$markers = Join-Path $dir 'phase-markers.csv'
$allowed = @('installer_started','installer_finished','idle_start','idle_end','hash_start','hash_end','stable_start','stable_end','cancel_start','cancel_done','resume_start','resume_done','capture_stopped')
if ($Phase -notin $allowed) { throw "Unknown phase: $Phase" }
[pscustomobject]@{ UTC = [DateTime]::UtcNow.ToString('o'); Phase = $Phase } |
    Export-Csv -LiteralPath $markers -NoTypeInformation -Append
$processes = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'gami|authentic memory|msedgewebview2'
}
$processes | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir ("processes-$Phase.json")) -Encoding UTF8
