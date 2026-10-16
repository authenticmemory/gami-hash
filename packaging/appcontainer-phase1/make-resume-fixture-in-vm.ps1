param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$root = Join-Path $Directory 'resume-fixture'
$source = Join-Path $root 'source'
$output = Join-Path $root 'output'
New-Item -ItemType Directory -Path $source,$output -Force | Out-Null
$existing = @(Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) { throw 'Resume fixture source is not empty; refusing to overwrite it.' }
$payload = New-Object byte[] (256 * 1024 - 4)
for ($i = 0; $i -lt 1024; $i++) {
    $path = Join-Path $source ('file_{0:D4}.bin' -f $i)
    $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $header = [BitConverter]::GetBytes([int]$i)
        $stream.Write($header,0,$header.Length)
        $stream.Write($payload,0,$payload.Length)
    } finally { $stream.Dispose() }
}
[ordered]@{
    createdUtc = [DateTime]::UtcNow.ToString('o')
    source = $source
    output = $output
    files = 1024
    bytes = [long]1024 * 256 * 1024
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'fixture-info.json') -Encoding UTF8
