param(
    [string]$Version = '0.1.0.0',
    [switch]$Sign,
    [string]$ReleasedCliPath = ''
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw 'Use an MSIX four-part version ending in .0' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sdkVersion = '10.0.22621.0'
$vc = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$cppwinrt = "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\cppwinrt"
$makeappx = "C:\Program Files (x86)\Windows Kits\10\bin\$sdkVersion\x64\makeappx.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\$sdkVersion\x64\signtool.exe"
$openssl = 'C:\msys64\ucrt64\bin\openssl.exe'
foreach ($required in @($vc,$cppwinrt,$makeappx,$signtool)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing build dependency: $required" }
}

$out = Join-Path $repo ('build/bin/appcontainer-phase1/{0}-{1}' -f $Version, [guid]::NewGuid().ToString('N'))
$stage = Join-Path $out 'stage'
$assets = Join-Path $stage 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
$source = Join-Path $PSScriptRoot 'probe.cpp'
$exe = Join-Path $stage 'GamiPhase1Probe.exe'
$obj = Join-Path $out 'probe.obj'
$compile = 'call "' + $vc + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE /I "' + $cppwinrt + '" "' + $source + '" /Fe:"' + $exe + '" /Fo:"' + $obj + '" /link /SUBSYSTEM:WINDOWS'
& cmd.exe /d /s /c $compile
if ($LASTEXITCODE -ne 0) { throw 'Native probe compilation failed' }
if ($ReleasedCliPath) {
    if (-not (Test-Path -LiteralPath $ReleasedCliPath -PathType Leaf)) { throw "Missing released CLI: $ReleasedCliPath" }
    Copy-Item -LiteralPath $ReleasedCliPath -Destination (Join-Path $stage 'signed-v1.5.0-cli.exe')
}

[xml]$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
$manifest.Package.Identity.Version = $Version
$manifest.Save((Join-Path $stage 'AppxManifest.xml'))

Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Image]::FromFile((Join-Path $repo 'build/appicon.png'))
try {
    foreach ($asset in @(@('StoreLogo',50),@('Square44x44Logo',44),@('Square150x150Logo',150))) {
        $size = [int]$asset[1]
        $bitmap = New-Object Drawing.Bitmap($size,$size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.DrawImage($icon,0,0,$size,$size)
            $bitmap.Save((Join-Path $assets ($asset[0] + '.png')),[Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $icon.Dispose() }

$package = Join-Path $out "gami-phase1-probe-$Version-x64.msix"
& $makeappx pack /d $stage /p $package /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx package validation failed' }
$unpacked = Join-Path $out 'unpacked-check'
& $makeappx unpack /p $package /d $unpacked /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx round-trip failed' }
foreach ($file in (@('GamiPhase1Probe.exe','AppxManifest.xml') + $(if ($ReleasedCliPath) { @('signed-v1.5.0-cli.exe') } else { @() }))) {
    if ((Get-FileHash -LiteralPath (Join-Path $stage $file)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $unpacked $file)).Hash) { throw "Package content mismatch: $file" }
}

$certFingerprint = $null
if ($Sign) {
    if (-not (Test-Path -LiteralPath $openssl)) { throw "Missing OpenSSL: $openssl" }
    $key = Join-Path $out 'development-key.pem'
    $pem = Join-Path $out 'development-certificate.pem'
    $cer = Join-Path $out 'development-certificate.cer'
    $pfx = Join-Path $out 'development-signing.pfx'
    $pfxPassword = [guid]::NewGuid().ToString('N')
    $priorErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue' # OpenSSL prints key-generation progress to stderr.
    try {
        & $openssl req -quiet -x509 -newkey rsa:3072 -sha256 -noenc -days 30 `
            -subj '/CN=GAMI Hash Phase 1 Probe' -addext 'basicConstraints=critical,CA:FALSE' `
            -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=codeSigning' `
            -keyout $key -out $pem 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Development certificate generation failed' }
        & $openssl x509 -in $pem -outform der -out $cer
        if ($LASTEXITCODE -ne 0) { throw 'Development certificate export failed' }
        & $openssl pkcs12 -legacy -export -inkey $key -in $pem -out $pfx -passout "pass:$pfxPassword"
        if ($LASTEXITCODE -ne 0) { throw 'Development PFX generation failed' }
    } finally { $ErrorActionPreference = $priorErrorAction }
    $priorErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $signOutput = & $signtool sign /debug /fd SHA256 /a /f $pfx /p $pfxPassword $package 2>&1
        $signExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorErrorAction }
    $signOutput | Set-Content -LiteralPath (Join-Path $out 'signing-output.txt')
    if ($signExit -ne 0) { throw "Development signing failed; see $out/signing-output.txt" }
    $certFingerprint = (Get-FileHash -LiteralPath $cer -Algorithm SHA256).Hash.ToLowerInvariant()
}

$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $package -Leaf)" | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding ascii
[pscustomobject]@{
    prototype = $true
    release = $false
    package = $package
    sha256 = $hash
    signed = [bool]$Sign
    certificateFileSha256 = $certFingerprint
    appContainerManifest = $true
    installedTested = $false
    sourceCommit = (git -c "safe.directory=$repo" -C $repo rev-parse HEAD)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'build-report.json') -Encoding UTF8
Write-Output "Phase 1 prototype: $package"
Write-Output "SHA-256: $hash"
Write-Output 'Build and package round-trip passed. Runtime behavior is untested.'
