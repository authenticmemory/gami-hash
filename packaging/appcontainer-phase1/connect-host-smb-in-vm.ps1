param(
    [Parameter(Mandatory)] [string]$HostAccount,
    [string]$PasswordFile = 'C:\Users\gami_runner\Documents\gami-phase1-smb-secret.txt',
    [string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe'
)

$ErrorActionPreference = 'Stop'
$password = [IO.File]::ReadAllText($PasswordFile).Trim()
if (-not $password) { throw 'Password file is empty.' }
try {
    & cmdkey.exe /add:192.168.247.1 "/user:$HostAccount" "/pass:$password" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not save disposable SMB credential.' }
} finally {
    Remove-Item -LiteralPath $PasswordFile -Force
    $password = $null
}
$unc = '\\192.168.247.1\GamiPhase1Remote'
$mappedSource = $null
$mappedOutput = $null
$existingMapping = Get-SmbMapping -LocalPath 'R:' -ErrorAction SilentlyContinue
if (-not $existingMapping) {
    & net.exe use R: $unc /persistent:no | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not map remote test share.' }
    $mappedSource = 'R:\source'
    $mappedOutput = 'R:\output'
} elseif ($existingMapping.RemotePath -eq $unc) {
    $mappedSource = 'R:\source'
    $mappedOutput = 'R:\output'
} else {
    Write-Warning "R: already maps to $($existingMapping.RemotePath); continuing with UNC paths only."
}
$result = [ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    source = "$unc\source"
    output = "$unc\output"
    mappedSource = $mappedSource
    mappedOutput = $mappedOutput
    sourceReachable = Test-Path -LiteralPath "$unc\source"
    outputReachable = Test-Path -LiteralPath "$unc\output"
    sourceFiles = @()
}
if ($result.sourceReachable) {
    $result.sourceFiles = @(Get-ChildItem -LiteralPath "$unc\source" -File -Recurse | ForEach-Object {
        [ordered]@{
            relativePath = $_.FullName.Substring(("$unc\source").Length + 1).Replace('\','/')
            length = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'remote-smb-inspection.json') -Encoding UTF8
if (-not $result.sourceReachable -or -not $result.outputReachable) { throw 'Mapped share was created but source or output is inaccessible.' }

