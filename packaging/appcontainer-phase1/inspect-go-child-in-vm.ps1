param([string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe')

$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name AuthenticMemory.GAMIHash.AppContainerProbe
$cli = Join-Path $package.InstallLocation 'signed-v1.5.0-cli.exe'
$log = Join-Path $env:LOCALAPPDATA 'Packages\AuthenticMemory.GAMIHash.AppContainerProbe_tbw3fy9pb0hh8\LocalState\go-path-probe.log'
$events = @(Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    Id = 1
    StartTime = (Get-Date).AddMinutes(-30)
} -ErrorAction SilentlyContinue | ForEach-Object {
    $record = $_
    [xml]$xml = $record.ToXml()
    $fields = @{}
    foreach ($node in $xml.Event.EventData.Data) { $fields[$node.Name] = $node.'#text' }
    if ($fields.ProcessId -in @('6580','8172','6720') -and $fields.Image -like '*AuthenticMemory.GAMIHash.AppContainerProbe*') {
        [ordered]@{
            utc = $record.TimeCreated.ToUniversalTime().ToString('o')
            recordId = $record.RecordId
            processId = $fields.ProcessId
            parentProcessId = $fields.ParentProcessId
            image = $fields.Image
            parentImage = $fields.ParentImage
            commandLine = $fields.CommandLine
        }
    }
})
[ordered]@{
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    package = $package.PackageFullName
    manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $package.InstallLocation 'AppxManifest.xml') -Algorithm SHA256).Hash.ToLowerInvariant()
    cliSha256 = (Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant()
    logSha256 = (Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant()
    goOutputExists = (Test-Path -LiteralPath 'C:\Users\Public\Documents\GamiPhase1Probe\local-fixture\output\go-path-probe.csv')
    events = $events
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Directory 'go-child-inspection.json') -Encoding UTF8
