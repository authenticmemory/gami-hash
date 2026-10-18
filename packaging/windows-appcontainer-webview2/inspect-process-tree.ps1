param(
    [string]$OutputDirectory = 'C:\Users\Public\Documents\GamiHashAppContainerEvidence',
    [int]$DurationSeconds = 15
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AppContainerToken {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr token, int informationClass, out int value, int valueLength, out int returnedLength);
}
'@

function Read-AppContainerFlag([int]$ProcessId) {
    $processHandle = [AppContainerToken]::OpenProcess(0x1000, $false, $ProcessId)
    if ($processHandle -eq [IntPtr]::Zero) { return @{ error = 'OpenProcess failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() } }
    $tokenHandle = [IntPtr]::Zero
    try {
        if (-not [AppContainerToken]::OpenProcessToken($processHandle, 0x0008, [ref]$tokenHandle)) {
            return @{ error = 'OpenProcessToken failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
        }
        $value = 0; $length = 0
        if (-not [AppContainerToken]::GetTokenInformation($tokenHandle, 29, [ref]$value, 4, [ref]$length)) {
            return @{ error = 'TokenIsAppContainer failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
        }
        return @{ isAppContainer = [bool]$value }
    } finally {
        if ($tokenHandle -ne [IntPtr]::Zero) { [void][AppContainerToken]::CloseHandle($tokenHandle) }
        [void][AppContainerToken]::CloseHandle($processHandle)
    }
}

$package = Get-AppxPackage -Name AuthenticMemory.GAMIHash.Windows
if (-not $package) { throw 'GAMI Hash Windows AppContainer package is not installed for this account.' }

$seen = @{}
$records = @()
$deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
do {
    $all = @(Get-CimInstance Win32_Process)
    $roots = @($all | Where-Object Name -eq 'GamiHash.exe')
    $included = @{}
    foreach ($root in $roots) { $included[[int]$root.ProcessId] = $true }
    do {
        $added = $false
        foreach ($process in $all) {
            if ($included.ContainsKey([int]$process.ParentProcessId) -and -not $included.ContainsKey([int]$process.ProcessId)) {
                $included[[int]$process.ProcessId] = $true
                $added = $true
            }
        }
    } while ($added)

    foreach ($process in $all | Where-Object { $included.ContainsKey([int]$_.ProcessId) }) {
        $key = [string]$process.ProcessId
        if ($seen.ContainsKey($key)) { continue }
        $token = Read-AppContainerFlag -ProcessId ([int]$process.ProcessId)
        $records += [pscustomobject][ordered]@{
            observedUtc = [DateTime]::UtcNow.ToString('o')
            name = $process.Name
            pid = [int]$process.ProcessId
            parentPid = [int]$process.ParentProcessId
            executablePath = $process.ExecutablePath
            commandLine = $process.CommandLine
            isAppContainer = $token.isAppContainer
            tokenError = $token.error
        }
        $seen[$key] = $true
    }
    if ($DurationSeconds -gt 0) { Start-Sleep -Milliseconds 200 }
} while ($DurationSeconds -gt 0 -and [DateTime]::UtcNow -lt $deadline)

$localCache = Join-Path $env:LOCALAPPDATA ('Packages\' + $package.PackageFamilyName + '\LocalCache')
$log = Get-ChildItem -LiteralPath $localCache -Filter app.log -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$result = [ordered]@{
    collectedUtc = [DateTime]::UtcNow.ToString('o')
    packageFullName = $package.PackageFullName
    packageFamilyName = $package.PackageFamilyName
    installLocation = $package.InstallLocation
    processes = $records
    allObservedProcessesContained = ($records.Count -gt 0 -and @($records | Where-Object { $_.isAppContainer -ne $true }).Count -eq 0)
    appLogPath = if ($log) { $log.FullName } else { $null }
    appLog = if ($log) { Get-Content -LiteralPath $log.FullName -Raw } else { $null }
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'process-tree.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 6
