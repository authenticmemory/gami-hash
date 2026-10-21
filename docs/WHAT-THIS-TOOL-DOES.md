# Authentic Memory Hashing Tool: IT summary

## Current Windows release

Production version **1.6.0** and accepted test candidate **1.6.1** use a native WPF frontend and a private Go hashing worker. They do not include WebView2, Wails, AppContainer, MSIX, an updater, telemetry, or an upload client. Installation is per-user and self-contained.

Installed programs:

- `GamiHash.exe`: native GUI
- `GamiHashEngine.exe`: private worker
- `gami-hash.exe`: optional CLI copy of the worker

## Data access

The engine recursively reads regular files, calculates SHA-256, and writes a five-column CSV outside the source tree. Source opens request read access. Links, reparse points, and special files are skipped. Unreadable files are recorded in a separate error log.

The application stores only manifest output and resume metadata. It installs no service or driver and requires no account.

## Network statement

The application has no feature that sends files, manifests, analytics, or telemetry. In documented acceptance scenarios, no GAMI-owned process generated a Sysmon network or DNS event during idle, local hashing, UNC SMB hashing, or mapped-drive hashing.

This is measured runtime evidence, not an OS-enforced network prohibition. SMB clients and cloud sync providers can communicate independently when Windows satisfies filesystem reads or hydrates an online-only file.

## Manifest schema

```text
relative_path,size_bytes,file_hash,mtime_utc,source_record_id
```

The CSV is UTF-8 with BOM, RFC 4180, CRLF terminated, and deterministically sorted. Absolute source paths and usernames are not included.

## Verify the installed version

```powershell
$file = '.\gami-hash-windows-amd64-installer.exe'
Get-AuthenticodeSignature $file | Format-List Status,SignerCertificate,TimeStamperCertificate
Get-FileHash $file -Algorithm SHA256
```

Expected SHA-256:

```text
1C6EE47771AE1458F04E7E1D9457038D961398D25D3A6F275C3B816363B97DF6
```

Require a valid signature and timestamp from Authentic Memory. SmartScreen reputation warnings are separate from signature validity.
