# WPF native test installer acceptance evidence

Date: 2026-10-18

## Exact artifact

- Installer: `gami-hash-native-test-0.2.0-x64-installer.exe`
- SHA-256: `fd92ffe9d996e187b68a710e932b46623cd0267d115463e6f1acac19166602ac`
- Size: 68,767,861 bytes
- Signature: unsigned development artifact
- Installation: per-user, self-contained .NET 8 WPF application plus Go worker
- Network renderer/runtime: none; the installer does not include WebView2

The installer completed locally and in the disposable Windows 11 x64 VMware
guest under the standard `gami_runner` account. The VM copy was hashed before
installation. Its installed application and worker hashes matched the local
installation.

## Results

| Scenario | Observed result | Process attribution | Manifest verification |
| --- | --- | --- | --- |
| Idle, 30 seconds | No GAMI-attributed network or DNS event | WPF PID 1020 parented Go worker PID 3584; two Sysmon process events | Not applicable |
| Local hash, 37 seconds | No GAMI-attributed network or DNS event | WPF PID 5840 parented Go worker PID 5384; two Sysmon process events | 16 rows, 16 unique paths, zero size/hash mismatches |

PktMon captured ambient VM packets in both windows, so the packet sensor was
active. Sysmon IDs 1, 3, and 22 supplied process creation, network, and DNS
attribution. The local manifest SHA-256 was
`d5ac50569803356d860a96333b72979949dcb84677f21bea8263a601b83b7bdd`.

## Meaning and remaining gate

This supports the narrow statement that no network connection or DNS request
was observed from the native GAMI process tree in these two scenarios. It is
not an operating-system-enforced network prohibition.

This development artifact is not a release candidate. Product naming, visual
parity, remaining workflow behavior, installer metadata, and signing still
need production work. Network captures must be repeated against the exact
final signed installer because rebuilding changes the tested artifact.
