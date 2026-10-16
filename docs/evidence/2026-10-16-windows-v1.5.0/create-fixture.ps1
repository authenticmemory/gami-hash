$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$source = Join-Path $dir 'source'
$output = Join-Path $dir 'output'
if (Test-Path -LiteralPath $source) { throw 'Fixture already exists.' }
New-Item -ItemType Directory -Path $source,$output | Out-Null
Set-Content -LiteralPath (Join-Path $source 'hello.txt') -Value 'GAMI Hash disposable test fixture' -Encoding UTF8
$buffer = [byte[]]::new(65536)
for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = [byte]($i % 251) }
for ($i = 0; $i -lt 512; $i++) {
    $path = Join-Path $source ('block-{0:D4}.bin' -f $i)
    [IO.File]::WriteAllBytes($path, $buffer)
}
$large = Join-Path $source 'large-zero-filled.bin'
$stream = [IO.File]::Open($large, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try { $stream.SetLength(2GB) } finally { $stream.Dispose() }
[pscustomobject]@{
    CreatedUTC = [DateTime]::UtcNow.ToString('o')
    Source = $source
    Output = $output
    FileCount = @(Get-ChildItem -LiteralPath $source -File).Count
    TotalBytes = (Get-ChildItem -LiteralPath $source -File | Measure-Object -Property Length -Sum).Sum
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'fixture.json') -Encoding UTF8
