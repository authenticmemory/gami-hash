$ErrorActionPreference = 'Stop'
$app = Get-AppxPackage -Name AuthenticMemory.GAMIHash.AppContainerProbe
if (-not $app) { throw 'Probe is not installed for this account' }
$appId = $app.PackageFamilyName + '!Probe'
Start-Process -FilePath explorer.exe -ArgumentList ('shell:AppsFolder\' + $appId)
