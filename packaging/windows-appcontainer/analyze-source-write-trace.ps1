param(
    [Parameter(Mandatory)] [string] $EtlPath,
    [Parameter(Mandatory)] [int[]] $WorkerPid,
    [Parameter(Mandatory)] [int] $HostPid,
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $TraceEventAssembly = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\PrivateAssemblies\Microsoft.Diagnostics.Tracing.TraceEvent.dll',
    [string] $UnsafeAssembly = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\PublicAssemblies\System.Runtime.CompilerServices.Unsafe.dll'
)

$ErrorActionPreference = 'Stop'

[Reflection.Assembly]::LoadFrom($UnsafeAssembly) | Out-Null
[Reflection.Assembly]::LoadFrom($TraceEventAssembly) | Out-Null

$targetPids = @($HostPid) + @($WorkerPid)
$sourceClasses = [ordered]@{
    local = '(?i)\\local-fixture\\source(?:\\|$)'
    smb = '(?i)(?:\\\\GAMI-HASH-VM\\GamiPhase1Loopback\\source|\\loopback-smb-fixture\\source)(?:\\|$)'
    cloud = '(?i)G:\\My Drive\\gami-test(?:\\|$)'
}

$counts = [ordered]@{}
foreach ($name in $sourceClasses.Keys) {
    $counts[$name] = [ordered]@{
        opens = 0
        reads = 0
        read_bytes = [int64]0
        writes = 0
        write_bytes = [int64]0
        mutations = 0
        creating_opens = 0
    }
}
$violations = [Collections.Generic.List[object]]::new()

function Get-SourceClass([string] $path) {
    foreach ($name in $sourceClasses.Keys) {
        if ($path -match $sourceClasses[$name]) { return $name }
    }
    return $null
}

function Add-Violation([string] $operation, [int] $pid, [string] $path, [string] $detail) {
    $violations.Add([ordered]@{ operation = $operation; pid = $pid; path = $path; detail = $detail })
}

$source = [Microsoft.Diagnostics.Tracing.ETWTraceEventSource]::new((Resolve-Path -LiteralPath $EtlPath).Path)
$kernel = [Microsoft.Diagnostics.Tracing.Parsers.KernelTraceEventParser]::new($source)

$onCreate = [Action[Microsoft.Diagnostics.Tracing.Parsers.Kernel.FileIOCreateTraceData]] {
    param($event)
    if ($event.ProcessID -notin $targetPids) { return }
    $class = Get-SourceClass $event.FileName
    if ($null -eq $class) { return }
    $counts[$class].opens++
    if ($event.CreateDisposition.ToString() -ne 'OPEN_EXISTING') {
        $counts[$class].creating_opens++
        Add-Violation 'Create' $event.ProcessID $event.FileName $event.CreateDisposition.ToString()
    }
}
$onRead = [Action[Microsoft.Diagnostics.Tracing.Parsers.Kernel.FileIOReadWriteTraceData]] {
    param($event)
    if ($event.ProcessID -notin $targetPids) { return }
    $class = Get-SourceClass $event.FileName
    if ($null -eq $class) { return }
    $counts[$class].reads++
    $counts[$class].read_bytes += $event.IoSize
}
$onWrite = [Action[Microsoft.Diagnostics.Tracing.Parsers.Kernel.FileIOReadWriteTraceData]] {
    param($event)
    if ($event.ProcessID -notin $targetPids) { return }
    $class = Get-SourceClass $event.FileName
    if ($null -eq $class) { return }
    $counts[$class].writes++
    $counts[$class].write_bytes += $event.IoSize
    Add-Violation 'Write' $event.ProcessID $event.FileName ([string]$event.IoSize)
}
$onMutation = [Action[Microsoft.Diagnostics.Tracing.Parsers.Kernel.FileIOInfoTraceData]] {
    param($event)
    if ($event.ProcessID -notin $targetPids) { return }
    $class = Get-SourceClass $event.FileName
    if ($null -eq $class) { return }
    $counts[$class].mutations++
    Add-Violation $event.OpcodeName $event.ProcessID $event.FileName ''
}

$kernel.add_FileIOCreate($onCreate)
$kernel.add_FileIORead($onRead)
$kernel.add_FileIOWrite($onWrite)
$kernel.add_FileIOSetInfo($onMutation)
$kernel.add_FileIODelete($onMutation)
$kernel.add_FileIORename($onMutation)

$processed = $source.GetType().GetMethod('Process', [Type[]]@()).Invoke($source, @())
$source.Dispose()

$result = [ordered]@{
    schema = 1
    etl_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $EtlPath).Hash.ToLowerInvariant()
    etl_bytes = (Get-Item -LiteralPath $EtlPath).Length
    host_pid = $HostPid
    worker_pids = @($WorkerPid)
    processed = [bool]$processed
    sources = $counts
    violations = @($violations)
    passed = ($violations.Count -eq 0)
    interpretation = 'Pass means no FileIO Write, SetInfo, Delete, Rename, or creating-open event from the product host/worker PIDs targeted a tested source path. OPEN_EXISTING and Read events are expected.'
}

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 8

if (-not $result.passed) { exit 1 }
