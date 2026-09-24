# Run after build-windows-installer.ps1 and after signing BOTH payload binaries.
# Only NSIS is rerun: invoking Wails here would overwrite the signed executable.
$ErrorActionPreference = "Stop"
& "$PSScriptRoot/verify-windows-signatures.ps1" -Stage Payload
$gui = Join-Path $PSScriptRoot "build/bin/gami-hash.exe"
$cli = Join-Path $PSScriptRoot "build/windows/installer/gami-hash-cli.exe"
$before = @((Get-FileHash $gui).Hash, (Get-FileHash $cli).Hash)
$makensis = Get-Command makensis -ErrorAction SilentlyContinue
if ($makensis) {
  $compiler = $makensis.Source
} else {
  $compiler = "${env:ProgramFiles(x86)}\NSIS\makensis.exe"
}
if (-not (Test-Path -LiteralPath $compiler)) { throw "NSIS compiler not found." }
Push-Location (Join-Path $PSScriptRoot "build/windows/installer")
try {
  & $compiler "-DARG_WAILS_AMD64_BINARY=$gui" "-DWAILS_INSTALL_SCOPE=user" "-DREQUEST_EXECUTION_LEVEL=user" "project.nsi"
  if ($LASTEXITCODE -ne 0) { throw "Packaging signed payload failed." }
} finally {
  Pop-Location
}
$after = @((Get-FileHash $gui).Hash, (Get-FileHash $cli).Hash)
if ($before[0] -ne $after[0] -or $before[1] -ne $after[1]) {
  throw "Packaging modified a signed payload. Refusing to release."
}
