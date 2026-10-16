param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$credentialList = (& cmdkey.exe /list | Out-String)
$mappingList = (& net.exe use | Out-String)
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    storedHostCredentialPresent = $credentialList.Contains('192.168.247.1')
    mappedTestDrivePresent = $mappingList.Contains('\\192.168.247.1\GamiPhase1Remote')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Directory 'host-smb-cleanup-verification.json') -Encoding UTF8
