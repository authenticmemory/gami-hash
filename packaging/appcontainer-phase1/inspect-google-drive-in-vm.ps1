param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$source = 'G:\My Drive\gami-test'
$output = 'G:\My Drive\gami-test-destination'
$result = [ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    source = $source
    output = $output
    sourceReachable = Test-Path -LiteralPath $source
    outputReachable = Test-Path -LiteralPath $output
    sourceEntries = @()
    outputEntries = @()
}
if ($result.sourceReachable) {
    $result.sourceEntries = @(Get-ChildItem -LiteralPath $source -Force -Recurse | ForEach-Object {
        [ordered]@{
            relativePath = $_.FullName.Substring($source.Length + 1).Replace('\','/')
            directory = $_.PSIsContainer
            length = if ($_.PSIsContainer) { $null } else { $_.Length }
            attributes = [string]$_.Attributes
        }
    })
}
if ($result.outputReachable) {
    $result.outputEntries = @(Get-ChildItem -LiteralPath $output -Force | ForEach-Object {
        [ordered]@{ name = $_.Name; directory = $_.PSIsContainer; length = if ($_.PSIsContainer) { $null } else { $_.Length } }
    })
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'google-drive-inspection.json') -Encoding UTF8
