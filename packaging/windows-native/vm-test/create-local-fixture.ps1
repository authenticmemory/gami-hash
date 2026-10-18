$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Public\Documents\GamiHashNativeTest'
$fixture = Join-Path $root 'local-fixture'
$output = Join-Path $root 'local-output'
New-Item -ItemType Directory -Force $fixture,$output | Out-Null
$buffer = New-Object byte[] (1MB)
for ($index = 0; $index -lt 16; $index++) {
  $buffer[0] = [byte]$index
  [IO.File]::WriteAllBytes((Join-Path $fixture ("file-{0:D2}.bin" -f $index)), $buffer)
}
Write-Output "SOURCE=$fixture"
Write-Output "OUTPUT=$output"
