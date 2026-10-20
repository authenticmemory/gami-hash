param(
  [Parameter(Mandatory)][string]$Version,
  [Parameter(Mandatory)][string]$Commit,
  [string]$Output = 'build/release-metadata/windows-release-report.json'
)

$ErrorActionPreference = 'Stop'
$installer = @(Get-ChildItem (Join-Path $PSScriptRoot 'build/bin') -Filter 'gami-hash-windows-*-x64-installer.exe' -File)
if ($installer.Count -ne 1) { throw "Expected exactly one signed installer; found $($installer.Count)." }

$paths = @(
  $installer[0].FullName,
  (Join-Path $PSScriptRoot 'build/windows-native/payload/GamiHash.exe'),
  (Join-Path $PSScriptRoot 'build/windows-native/payload/GamiHashEngine.exe')
)
$files = foreach ($path in $paths) {
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
    throw "A valid timestamped signature is required before recording release identity: $path"
  }
  [ordered]@{
    name = Split-Path -Leaf $path
    bytes = (Get-Item -LiteralPath $path).Length
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    signerSubject = $signature.SignerCertificate.Subject
    signerThumbprint = $signature.SignerCertificate.Thumbprint
    timestampSubject = $signature.TimeStamperCertificate.Subject
  }
}

$target = Join-Path $PSScriptRoot $Output
New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
[ordered]@{
  schema = 1
  version = $Version
  commit = $Commit
  repository = $env:GITHUB_REPOSITORY
  workflowRun = if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) { "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)" } else { $null }
  generatedUtc = [DateTime]::UtcNow.ToString('o')
  files = $files
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding utf8
Get-Content -LiteralPath $target
