param(
    [Parameter(Mandatory = $true)]
    [string]$Directory
)

$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($Directory)
if (Test-Path -LiteralPath $target) { throw "Refusing to replace existing path: $target" }

$source = Join-Path $target 'source'
$output = Join-Path $target 'output'
$moved = Join-Path $target 'moved-source'
$nested = Join-Path $source 'nested folder'
New-Item -ItemType Directory -Path $source,$output,$nested | Out-Null

$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllBytes((Join-Path $source 'hello.txt'), $utf8.GetBytes("GAMI phase 0`n"))
[IO.File]::WriteAllBytes((Join-Path $source 'duplicate.txt'), $utf8.GetBytes("GAMI phase 0`n"))
[IO.File]::WriteAllBytes((Join-Path $source 'empty.bin'), [byte[]]::new(0))
$unicodeName = 'Gr' + [char]0x00fc + [char]0x00df + 'e.txt'
[IO.File]::WriteAllBytes((Join-Path $nested $unicodeName), $utf8.GetBytes("Archive sample`n"))
$buffer = [byte[]]::new(65536)
for ($i = 0; $i -lt $buffer.Length; $i++) { $buffer[$i] = [byte]($i % 251) }
[IO.File]::WriteAllBytes((Join-Path $nested 'pattern.bin'), $buffer)

$fixedTime = [DateTime]::Parse('2026-01-01T00:00:00Z').ToUniversalTime()
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File | Sort-Object FullName)
foreach ($file in $files) { $file.LastWriteTimeUtc = $fixedTime }
$expected = @($files | ForEach-Object {
    [pscustomobject]@{
        relative_path = $_.FullName.Substring($source.Length + 1).Replace('\','/')
        size_bytes = $_.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    }
})
$expected | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $target 'expected.json') -Encoding UTF8

# Keep the moved-root candidate outside the selected source. It is a copy,
# not a second input to the first run. Use it only after making a checkpoint.
Copy-Item -LiteralPath $source -Destination $moved -Recurse
[pscustomobject]@{
    source = $source
    output = $output
    moved_source = $moved
    expected = Join-Path $target 'expected.json'
    files = $expected.Count
} | Format-List
