param(
    [string]$OutputDirectory = '',
    [string]$Version = 'dev',
    [string]$Go = 'go',
    [string]$WindowsSDKVersion = '',
    [string]$VCVars64 = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repo 'build/bin/windows-appcontainer-product'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$goCommand = Get-Command $Go -ErrorAction Stop
if (-not $env:GOCACHE) { $env:GOCACHE = Join-Path $repo 'build/gocache' }
if (-not $env:GOMODCACHE) { $env:GOMODCACHE = Join-Path $repo 'build/gomodcache' }
& $goCommand.Source build -trimpath -ldflags "-X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version" `
    -o (Join-Path $OutputDirectory 'GamiHashContainedWorker.exe') $repo
if ($LASTEXITCODE -ne 0) { throw 'Contained Go worker build failed' }

$windowsKits = 'C:\Program Files (x86)\Windows Kits\10'
if (-not $WindowsSDKVersion) {
    $WindowsSDKVersion = Get-ChildItem -LiteralPath (Join-Path $windowsKits 'Include') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'cppwinrt')) } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty Name
}
if (-not $VCVars64) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw "Missing build dependency: $vswhere" }
    $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) | Select-Object -First 1
    if (-not $installation) { throw 'Visual Studio C++ build tools were not found.' }
    $VCVars64 = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
}
$cppwinrt = Join-Path $windowsKits "Include\$WindowsSDKVersion\cppwinrt"
foreach ($required in @($VCVars64, $cppwinrt)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing build dependency: $required" }
}
foreach ($source in @('storage_identity.cpp','storage_consent.cpp','broker_protocol.cpp','storage_broker_session.cpp','worker_launcher.cpp')) {
    $object = Join-Path $OutputDirectory ($source -replace '\.cpp$','.obj')
    $compile = 'call "' + $VCVars64 + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE /I "' + `
        $cppwinrt + '" /c "' + (Join-Path $PSScriptRoot $source) + '" /Fo:"' + $object + '"'
    & cmd.exe /d /s /c $compile
    if ($LASTEXITCODE -ne 0) { throw "Native product component failed to compile: $source" }
}
$library = Join-Path $OutputDirectory 'GamiHashStorageBroker.lib'
$objects = @('storage_identity.obj','storage_consent.obj','broker_protocol.obj','storage_broker_session.obj','worker_launcher.obj') |
    ForEach-Object { '"' + (Join-Path $OutputDirectory $_) + '"' }
$archive = 'call "' + $VCVars64 + '" >nul && lib /nologo /out:"' + $library + '" ' + ($objects -join ' ')
& cmd.exe /d /s /c $archive
if ($LASTEXITCODE -ne 0) { throw 'Native storage broker library build failed' }

$policyTest = Join-Path $OutputDirectory 'storage_consent_test.exe'
$testCompile = 'call "' + $VCVars64 + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE /I "' + `
    $cppwinrt + '" /I "' + $PSScriptRoot + '" "' + (Join-Path $PSScriptRoot 'storage_consent_test.cpp') +
    '" "' + $library + '" /Fe:"' + $policyTest + '" /link windowsapp.lib onecore.lib'
& cmd.exe /d /s /c $testCompile
if ($LASTEXITCODE -ne 0) { throw 'Native storage consent tests failed to compile' }
& $policyTest
if ($LASTEXITCODE -ne 0) { throw 'Native storage consent tests failed' }

$artifacts = Get-ChildItem -LiteralPath $OutputDirectory -File |
    Where-Object Extension -In '.exe','.obj','.lib' |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
$report = [pscustomobject]@{
    prototype = $false
    release = $false
    phase = 4
    version = $Version
    sourceCommit = (git -c "safe.directory=$repo" -C $repo rev-parse HEAD)
    artifacts = $artifacts
    runtimeTested = $false
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-report.json') -Encoding UTF8
$report
