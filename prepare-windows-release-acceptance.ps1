param(
  [Parameter(Mandatory)][string]$Installer,
  [string]$Destination = (Join-Path $PSScriptRoot 'build/windows-release-acceptance')
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Installer).Path
$signature = Get-AuthenticodeSignature -LiteralPath $source
if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
  throw 'The acceptance candidate must have a valid timestamped Authenticode signature.'
}
$expectedOrganization = "Authentic Memory gemeinn$([char]0x00fc)tzige UG (haftungsbeschr$([char]0x00e4)nkt)"
if ($signature.SignerCertificate.Subject -notmatch ('(?:^|,\s*)O=' + [regex]::Escape($expectedOrganization) + '(?:,|$)')) {
  throw "Unexpected signer: $($signature.SignerCertificate.Subject)"
}

New-Item -ItemType Directory -Force $Destination | Out-Null
$candidate = Join-Path $Destination (Split-Path -Leaf $source)
Copy-Item -LiteralPath $source -Destination $candidate -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'packaging/windows-native/vm-test/*.ps1') -Destination $Destination -Force

$identity = [ordered]@{
  schema = 1
  installer = Split-Path -Leaf $candidate
  bytes = (Get-Item -LiteralPath $candidate).Length
  sha256 = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
  signerSubject = $signature.SignerCertificate.Subject
  signerThumbprint = $signature.SignerCertificate.Thumbprint
  timestampSubject = $signature.TimeStamperCertificate.Subject
  preparedUtc = [DateTime]::UtcNow.ToString('o')
}
$identity | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Destination 'artifact-identity.json') -Encoding utf8
Compress-Archive -Path (Join-Path $Destination '*') -DestinationPath "$Destination.zip" -Force
$identity | ConvertTo-Json -Depth 4
