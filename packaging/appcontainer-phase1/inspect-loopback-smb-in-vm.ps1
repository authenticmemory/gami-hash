param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$unc = "\\$env:COMPUTERNAME\GamiPhase1Loopback"
$source = "$unc\source"
$output = "$unc\output"
$result = [ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    source = $source
    output = $output
    shareReachable = Test-Path -LiteralPath $unc
    sourceReachable = Test-Path -LiteralPath $source
    outputReachable = Test-Path -LiteralPath $output
    sourceFiles = @()
}
if ($result.sourceReachable) {
    $result.sourceFiles = @(Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
        [ordered]@{
            relativePath = $_.FullName.Substring($source.Length + 1).Replace('\','/')
            length = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'loopback-smb-inspection.json') -Encoding UTF8
