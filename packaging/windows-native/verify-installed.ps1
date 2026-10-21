param(
    [string] $ExpectedVersion,
    [switch] $ExpectDesktopShortcut,
    [switch] $ExpectCli
)

$ErrorActionPreference = 'Stop'
$install = Join-Path $env:LOCALAPPDATA 'Programs\Authentic Memory\GAMI Hash'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser,
    [Microsoft.Win32.RegistryView]::Registry64)
$uninstallKey = $registry.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\GAMIHash')
if (-not $uninstallKey) { throw 'The 64-bit uninstall registry entry is missing.' }
$entry = [pscustomobject]@{}
foreach ($name in $uninstallKey.GetValueNames()) {
    $entry | Add-Member -NotePropertyName $name -NotePropertyValue $uninstallKey.GetValue($name)
}
$failures = [Collections.Generic.List[string]]::new()

function Test-Expected([bool] $condition, [string] $message) {
    if (-not $condition) { $failures.Add($message) }
}

Test-Expected ($entry.DisplayName -eq 'Authentic Memory Hashing Tool') 'Incorrect Installed Apps display name.'
Test-Expected ($entry.Publisher -eq 'Authentic Memory') 'Incorrect publisher.'
Test-Expected ($entry.InstallLocation -eq $install) 'Incorrect installation directory.'
Test-Expected ($entry.EstimatedSize -gt 0) 'Installed size is missing.'
Test-Expected ($entry.InstallDate -match '^\d{8}$') 'Install date is missing or invalid.'
if ($ExpectedVersion) { Test-Expected ($entry.DisplayVersion -eq "$ExpectedVersion.0") 'Installed version does not match.' }

$gui = Join-Path $install 'GamiHash.exe'
$worker = Join-Path $install 'GamiHashEngine.exe'
$cli = Join-Path $install 'gami-hash.exe'
$uninstaller = Join-Path $install 'Uninstall.exe'
$startShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Authentic Memory\Authentic Memory Hashing Tool.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Authentic Memory Hashing Tool.lnk'
Test-Expected (Test-Path -LiteralPath $gui -PathType Leaf) 'GUI executable is missing.'
Test-Expected (Test-Path -LiteralPath $worker -PathType Leaf) 'Hashing worker is missing.'
Test-Expected (Test-Path -LiteralPath $uninstaller -PathType Leaf) 'Uninstaller is missing.'
Test-Expected (Test-Path -LiteralPath $startShortcut -PathType Leaf) 'Start menu shortcut is missing.'
Test-Expected ((Test-Path -LiteralPath $desktopShortcut -PathType Leaf) -eq $ExpectDesktopShortcut.IsPresent) 'Desktop shortcut selection was not applied.'
Test-Expected ((Test-Path -LiteralPath $cli -PathType Leaf) -eq $ExpectCli.IsPresent) 'CLI selection was not applied.'

$environmentKey = $registry.OpenSubKey('Environment')
$userPath = [string]$environmentKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$pathEntries = @(($userPath -split ';') | ForEach-Object { $_.TrimEnd('\') })
Test-Expected (($pathEntries -contains $install.TrimEnd('\')) -eq $ExpectCli.IsPresent) 'Persisted user PATH does not match the CLI selection.'

$uninstallerSignature = Get-AuthenticodeSignature -LiteralPath $uninstaller
Test-Expected ($uninstallerSignature.Status -eq 'Valid' -and $null -ne $uninstallerSignature.TimeStamperCertificate) 'Uninstaller signature or timestamp is invalid.'

$msix = @(Get-AppxPackage -Name AuthenticMemory.GAMIHash.Windows) + @(Get-AppxPackage -Name AuthenticMemory.GAMIHash.Phase2Product)
Test-Expected ($msix.Count -eq 0) 'A conflicting production-name MSIX remains installed.'

$result = [pscustomobject]@{
    Passed = $failures.Count -eq 0
    Version = $entry.DisplayVersion
    InstallLocation = $entry.InstallLocation
    EstimatedSizeKB = $entry.EstimatedSize
    DesktopShortcut = Test-Path -LiteralPath $desktopShortcut
    CLI = Test-Path -LiteralPath $cli
    Failures = @($failures)
}
$result | ConvertTo-Json -Depth 4
if ($failures.Count) { exit 1 }
