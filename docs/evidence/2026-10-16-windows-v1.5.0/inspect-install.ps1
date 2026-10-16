$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$install = 'C:\Users\tech\AppData\Local\Programs\Authentic Memory Hashing Tool'
$files = foreach ($name in @('GAMI Hash.exe','gami-hash.exe','uninstall.exe')) {
    $path = Join-Path $install $name
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    [pscustomobject]@{
        Name = $name
        SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        SignatureStatus = [string]$sig.Status
        Signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
        ProductVersion = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
    }
}
[pscustomobject]@{
    InspectedUTC = [DateTime]::UtcNow.ToString('o')
    InstallPath = $install
    Files = @($files)
    WebView2Version = (Get-ChildItem 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' -Directory |
        Where-Object Name -Match '^\d+\.\d+\.\d+\.\d+$' | Select-Object -ExpandProperty Name)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'installed-files.json') -Encoding UTF8
