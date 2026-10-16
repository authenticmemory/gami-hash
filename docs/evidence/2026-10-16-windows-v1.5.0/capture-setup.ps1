$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$expectedHash = 'ae0fb30322f923c63d55c43ee3e531be4f7114ae0cb911ed6524bdb0fedea308'
$installer = Join-Path $dir 'gami-hash-windows-amd64-installer.exe'
$sysmon = Join-Path $dir 'Sysmon64.exe'
$procmon = Join-Path $dir 'Procmon64.exe'

Start-Transcript -LiteralPath (Join-Path $dir 'setup-transcript.txt') -Force | Out-Null
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Capture setup requires administrator rights.'
    }

    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expectedHash) { throw "Installer SHA-256 mismatch: $hash" }
    $verifiedFiles = foreach ($file in @($installer, $sysmon, $procmon)) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($signature.Status -ne 'Valid') { throw "Invalid signature: $file ($($signature.Status))" }
        [pscustomobject]@{
            File = Split-Path -Leaf $file
            SHA256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            SignatureStatus = [string]$signature.Status
            Signer = $signature.SignerCertificate.Subject
        }
    }
    $verifiedFiles | Format-List | Out-String | Set-Content -LiteralPath (Join-Path $dir 'file-verification.txt')

    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        WindowsCaption = $os.Caption
        WindowsVersion = $os.Version
        WindowsBuild = $os.BuildNumber
        CaptureSetupUTC = [DateTime]::UtcNow.ToString('o')
        User = $identity.Name
        IsAdministrator = $true
        WebView2ApplicationVersions = @(
            Get-ChildItem 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' -Directory -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
        )
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'environment.json') -Encoding UTF8

    $existingService = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Continue'
    if ($existingService) {
        & $sysmon -c (Join-Path $dir 'sysmon-config.xml') *> (Join-Path $dir 'sysmon-install.log')
    } else {
        & $sysmon -accepteula -i (Join-Path $dir 'sysmon-config.xml') *> (Join-Path $dir 'sysmon-install.log')
    }
    $sysmonExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($sysmonExitCode -ne 0) { throw "Sysmon configuration failed with exit code $sysmonExitCode" }
    $service = Get-Service -Name 'Sysmon64' -ErrorAction Stop
    if ($service.Status -ne 'Running') { throw "Sysmon service status: $($service.Status)" }
    wevtutil.exe gl 'Microsoft-Windows-Sysmon/Operational' *> (Join-Path $dir 'sysmon-channel.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Sysmon event channel not available.' }
    'READY: signed installer verified, Sysmon running, and event channel available.'
} catch {
    "SETUP FAILED: $($_.Exception.Message)"
    throw
} finally {
    Stop-Transcript | Out-Null
}
