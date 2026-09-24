param(
  [ValidateSet("Payload", "Installer", "All")]
  [string]$Stage = "All"
)

$ErrorActionPreference = "Stop"
$files = @()
if ($Stage -in @("Payload", "All")) {
  $files += Join-Path $PSScriptRoot "build/bin/gami-hash.exe"
  $files += Join-Path $PSScriptRoot "build/windows/installer/gami-hash-cli.exe"
}
if ($Stage -in @("Installer", "All")) {
  $installers = @(Get-ChildItem (Join-Path $PSScriptRoot "build/bin") -Filter "*-installer.exe" -File)
  if ($installers.Count -ne 1) { throw "Expected exactly one Windows installer; found $($installers.Count)." }
  $files += $installers[0].FullName
}
foreach ($file in $files) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing release file: $file" }
  $signature = Get-AuthenticodeSignature -LiteralPath $file
  if ($signature.Status -ne "Valid" -or -not $signature.TimeStamperCertificate) {
    throw "A valid timestamped Authenticode signature is required: $file ($($signature.Status))"
  }
  # Compare the decoded organization attribute, not a short-lived certificate thumbprint.
  $subject = $signature.SignerCertificate.Subject
  $expected = "Authentic Memory gemeinn$([char]0x00fc)tzige UG (haftungsbeschr$([char]0x00e4)nkt)"
  if ($subject -notmatch ('(?:^|,\s*)O=' + [regex]::Escape($expected) + '(?:,|$)')) {
    throw "Unexpected signing organization for ${file}: $subject"
  }
  Write-Output "Verified signature and timestamp: $file"
}
