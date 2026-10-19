# Authentic Memory Hashing Tool (`gami-hash`)

Authentic Memory Hashing Tool creates a local CSV inventory of a collection. It reads every eligible file under a selected folder, calculates its SHA-256 checksum, and writes one deterministic manifest. It does not upload files or manifests.

The current production release is **v1.6.0**.

## Platforms

| Platform | Interface | Release format |
| --- | --- | --- |
| Windows x64 | Native WPF GUI plus Go worker; optional CLI | Signed self-contained NSIS installer |
| Linux x64 | Wails GUI and portable CLI | `.deb`, `.rpm`, GUI tarball, CLI tarball |
| macOS | Wails GUI | Build workflow exists; public signing and notarization are not complete |

Windows does not package or launch Wails, WebView2, AppContainer, MSIX, a storage broker, an updater, or a network client. The installed process tree is `GamiHash.exe` plus its private `GamiHashEngine.exe` worker.

## Manifest

```text
relative_path,size_bytes,file_hash,mtime_utc,source_record_id
```

- `file_hash` is `sha256:` followed by 64 lowercase hexadecimal characters.
- `source_record_id` equals the encoded relative path.
- Output is RFC 4180 CSV, UTF-8 with BOM, CRLF terminated, and deterministically sorted.
- Absolute paths, usernames, file contents, and collection metadata are excluded.

## Safety and recovery

- Source files are opened read-only. Symlinks, junctions, reparse points, and special files are skipped and reported.
- The engine rejects output paths inside the selected source tree.
- Interrupted runs can resume. Existing rows are reused only when path, size, and modification time still match; changed files are hashed again.
- A file that changes while being read is retried once, then omitted and reported instead of receiving an unreliable checksum.
- Unreadable files are listed in an adjacent `_errors.log`; the remaining manifest is preserved.

## Windows use

Install `gami-hash-windows-amd64-installer.exe`. The installer is per-user, self-contained, and requires no administrator privileges or runtime download. It can optionally add the CLI to the user PATH.

Open **Authentic Memory Hashing Tool** from Start, or use:

```powershell
gami-hash --root "D:\Collection" --output "C:\Manifests\collection.csv"
```

Useful flags are `--workers N`, `--fresh`, `--rehash-existing`, `--quiet`, `--version`, and `--help`. Exit codes are `0` for success, `1` for fatal error, `2` for completion with unreadable files, and `130` for an interrupted run.

See [the archivist guide](docs/ARCHIVIST-GUIDE.md), [the IT summary](docs/WHAT-THIS-TOOL-DOES.md), and [Windows acceptance](docs/WINDOWS-ACCEPTANCE.md).

## Files written

| File | Purpose |
| --- | --- |
| Selected `.csv` | Final manifest |
| `<name>_errors.log` | Warnings and skipped files, when present |
| `<output>.part.json` | Resume checkpoint during an unfinished run |
| `last-run.json` in the user config directory | Enables the GUI resume offer |

## Build and test

Requirements are Go 1.27.2, .NET 8 SDK, NSIS, and Node.js for the Wails platforms.

```powershell
go test ./...
node --test scripts/create-download-manifest.test.mjs
dotnet build .\windows\GamiHash.Windows\GamiHash.Windows.csproj -c Release
.\build-windows-installer.ps1 -Version v1.6.0
```

Windows CI signs `GamiHash.exe`, `GamiHashEngine.exe`, and the final installer, then verifies signatures and timestamps. Stable tags promote the exact Windows candidate bytes that passed acceptance instead of rebuilding them. See [VERIFY.md](VERIFY.md), [Windows signing](docs/windows-signing.md), and [release publishing](docs/RELEASE-DOWNLOADS.md).

## Release

The v1.6.0 release is at https://github.com/authenticmemory/gami-hash/releases/tag/v1.6.0.

The published Windows installer SHA-256 is:

```text
1c6ee47771ae1458f04e7e1d9457038d961398d25d3a6f275c3b816363b97df6
```
