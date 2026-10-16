param(
    [string]$Go = 'go',
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Output) { $Output = Join-Path $repo 'build/bin/appcontainer-phase2/Phase2GoProbe.exe' }
$outDir = Split-Path -Parent $Output
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$env:GOTOOLCHAIN = 'local'
$env:GOCACHE = Join-Path $repo 'build/bin/go-cache'
Push-Location $repo
try {
    & $Go build -o $Output ./packaging/appcontainer-phase2/go-probe
    if ($LASTEXITCODE -ne 0) { throw 'Phase 2 Go probe build failed' }
} finally { Pop-Location }
Write-Output (Get-FileHash -LiteralPath $Output -Algorithm SHA256 | Select-Object -ExpandProperty Hash)
