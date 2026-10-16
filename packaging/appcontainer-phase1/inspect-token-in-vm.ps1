param(
    [string]$Directory = 'C:\Users\Public\Documents\GamiPhase1Probe',
    [int]$DurationSeconds = 0
)

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProbeToken {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool GetTokenInformation(IntPtr token, int informationClass,
    out int value, int valueLength, out int returnedLength);
}
'@

$results = @()
$seen = @{}
$deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
do {
  $processes = @(Get-CimInstance Win32_Process -Filter "Name='GamiPhase1Probe.exe'")
  foreach ($process in $processes) {
    if ($seen.ContainsKey([string]$process.ProcessId)) { continue }
    $entry = [ordered]@{ pid = $process.ProcessId; parentPid = $process.ParentProcessId; commandLine = $process.CommandLine }
    $handle = [ProbeToken]::OpenProcess(0x1000,$false,[int]$process.ProcessId)
    if ($handle -eq [IntPtr]::Zero) { $entry.error = 'OpenProcess failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
    else {
        $token = [IntPtr]::Zero
        try {
            if (-not [ProbeToken]::OpenProcessToken($handle,0x0008,[ref]$token)) {
                $entry.error = 'OpenProcessToken failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            } else {
                $value = 0; $length = 0
                if ([ProbeToken]::GetTokenInformation($token,29,[ref]$value,4,[ref]$length)) {
                    $entry.isAppContainer = [bool]$value
                } else { $entry.error = 'TokenIsAppContainer failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
            }
        } finally {
            if ($token -ne [IntPtr]::Zero) { [void][ProbeToken]::CloseHandle($token) }
            [void][ProbeToken]::CloseHandle($handle)
        }
    }
    $results += [pscustomobject]$entry
    $seen[[string]$process.ProcessId] = $true
  }
  $results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Directory 'token-results.json') -Encoding UTF8
  if ($DurationSeconds -gt 0) { Start-Sleep -Milliseconds 100 }
} while ($DurationSeconds -gt 0 -and [DateTime]::UtcNow -lt $deadline)
