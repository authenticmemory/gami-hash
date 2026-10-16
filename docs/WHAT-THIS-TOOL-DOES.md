# GAMI Hashing Tool: information for IT staff

*One page.*

## What it is

A Windows desktop application and separate command-line tool that compute
SHA-256 checksums for files under a folder chosen by the user and write a CSV
manifest. They prepare collection handovers to GAMI without shipping the
source files themselves.

## What it does, completely

1. Reads every regular file under the user-chosen folder (opened read-only).
2. Writes exactly one CSV file to the user-chosen output location, which the
   program refuses to place inside the scanned folder. Next to it, when
   needed: an error log and a temporary resume marker.
3. Remembers an interrupted run in one small JSON file in the user's config
   folder (two paths, nothing else), so the next start can offer to continue
   with one click. Removed when the run completes.
4. Shows a progress bar, and at the end an "Open folder" button that reveals
   the result file in the system file manager. On Windows, the GUI also starts
   Microsoft's WebView2 runtime, whose processes made account-related and
   component-update requests in the v1.5.0 VM test.

## What it does not do

- The hashing code contains no upload, telemetry, account, remote-font,
  remote-image, or remote-help feature. **The v1.5.0 Windows GUI's WebView2
  child processes did make external network connections in a VM test.** Do
  not describe this release as making no internet connections. The
  [follow-up capture](evidence/2026-10-16-windows-v1.5.0/followup/README.md)
  identified Microsoft account profile requests with authorization headers
  and a browser component update request.
- No writes into the scanned folder. Enforced in code, and every file is
  opened with read-only flags. You can run it against a read-only share or a
  write-protected drive.
- Output paths are resolved before use, including Windows junctions. Output
  files are built separately and then published without truncating an existing
  symlink or hard-link target in place.
- Hashing does not require a GAMI account or install a service or driver.
  The Windows GUI's WebView2 processes nevertheless sent account-related
  requests in the tested VM. Windows and macOS releases are packaged as
  installable/native apps; the CLI artifact remains portable.
- The output CSV contains five columns: `relative_path`, `size_bytes`,
  `file_hash` (SHA-256), `mtime_utc`, and `source_record_id`. The last column
  repeats the relative path for handover compatibility.

## Verifying the binary

The v1.5.0 Windows installer is Authenticode signed and timestamped by
Authentic Memory. Windows SmartScreen can still warn if the installer has
little reputation. Check the signature and download hash:

```powershell
$installer = '.\gami-hash-windows-amd64-installer.exe'
Get-AuthenticodeSignature -LiteralPath $installer | Format-List Status,SignerCertificate,TimeStamperCertificate
Get-FileHash -LiteralPath $installer -Algorithm SHA256
```

Require a `Valid` signature with the expected publisher, and compare the hash
with the checksum published for the same release. A valid signature does not
establish that SmartScreen will suppress a reputation warning. Release
reproducibility is not claimed; see `VERIFY.md` for current build limits.

## Resource use

Reads files sequentially with 2 parallel workers by default (safe for
spinning disks and network shares). CPU: one to two cores while hashing.
Memory: typically well under 200 MB. Runtime: roughly the time needed to
read the data once. A 4 TB collection on a USB disk takes about a working
day, and the run can be interrupted and resumed at any time.
