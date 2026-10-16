param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$status = Get-Content -LiteralPath (Join-Path $Directory 'install-result.json') -Raw | ConvertFrom-Json
$activity = [regex]::Match($status.error, '\[ActivityId\]\s+([0-9a-fA-F-]{36})').Groups[1].Value
if (-not $activity) { throw 'No deployment ActivityId in install-result.json' }
Get-AppPackageLog -ActivityID $activity | Format-List * |
    Out-File -LiteralPath (Join-Path $Directory 'install-activity.txt') -Encoding UTF8 -Width 220
Get-ChildItem Cert:\LocalMachine\TrustedPeople |
    Where-Object Subject -eq 'CN=GAMI Hash Phase 1 Probe' |
    Select-Object Subject,Thumbprint,NotAfter |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Directory 'machine-trust.json') -Encoding UTF8
