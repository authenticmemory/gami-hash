param(
    [string]$OutputDirectory = '',
    [string]$Version = 'dev'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repo 'build/bin/windows-appcontainer-product'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$go = Join-Path $repo '../.tools/go1.27.0/go/bin/go.exe'
if (-not (Test-Path -LiteralPath $go)) {
    $go = Join-Path $repo 'build/bin/go-toolchain/go/bin/go.exe'
}
if (-not (Test-Path -LiteralPath $go)) { throw 'Pinned Go toolchain was not found' }
if (-not $env:GOCACHE) { $env:GOCACHE = Join-Path $repo 'build/gocache' }
if (-not $env:GOMODCACHE) { $env:GOMODCACHE = Join-Path $repo 'build/gomodcache' }
& $go build -trimpath -ldflags "-X github.com/authenticmemory/gami-hash/internal/engine.Version=$Version" `
    -o (Join-Path $OutputDirectory 'GamiHashContainedWorker.exe') $repo
if ($LASTEXITCODE -ne 0) { throw 'Contained Go worker build failed' }

$sdkVersion = '10.0.22621.0'
$vc = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$cppwinrt = "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\cppwinrt"
foreach ($required in @($vc, $cppwinrt)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing build dependency: $required" }
}
foreach ($source in @('storage_identity.cpp','storage_consent.cpp','broker_protocol.cpp','storage_broker_session.cpp','worker_launcher.cpp')) {
    $object = Join-Path $OutputDirectory ($source -replace '\.cpp$','.obj')
    $compile = 'call "' + $vc + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE /I "' + `
        $cppwinrt + '" /c "' + (Join-Path $PSScriptRoot $source) + '" /Fo:"' + $object + '"'
    & cmd.exe /d /s /c $compile
    if ($LASTEXITCODE -ne 0) { throw "Native product component failed to compile: $source" }
}
$library = Join-Path $OutputDirectory 'GamiHashStorageBroker.lib'
$objects = @('storage_identity.obj','storage_consent.obj','broker_protocol.obj','storage_broker_session.obj','worker_launcher.obj') |
    ForEach-Object { '"' + (Join-Path $OutputDirectory $_) + '"' }
$archive = 'call "' + $vc + '" >nul && lib /nologo /out:"' + $library + '" ' + ($objects -join ' ')
& cmd.exe /d /s /c $archive
if ($LASTEXITCODE -ne 0) { throw 'Native storage broker library build failed' }

$policyTest = Join-Path $OutputDirectory 'storage_consent_test.exe'
$testCompile = 'call "' + $vc + '" >nul && cl /nologo /std:c++20 /EHsc /MD /DUNICODE /D_UNICODE /I "' + `
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
