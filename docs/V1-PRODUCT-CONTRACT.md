# GAMI Hash version 1 product contract

**Status:** Current
**Last updated:** 2026-10-19

GAMI Hash has one job: read a user-selected folder tree and create a local CSV manifest containing technical metadata and a SHA-256 checksum for every eligible file. It does not interpret, upload, or modify the collection.

## Supported release

Windows 10/11 x64 is the primary supported desktop platform. Version 1.6.0 ships as a signed, timestamped, per-user, self-contained NSIS installer containing a native WPF GUI and Go worker. The optional CLI uses the same engine.

Linux x64 artifacts include a portable CLI, Ubuntu `.deb`, Fedora-style `.rpm`, and GUI tarball. The Linux GUI uses Wails with GTK/WebKitGTK. macOS builds remain outside the fully supported signed release tier until signing and notarization are complete.

## Workflow

1. Explain the operation and local-output boundary.
2. Select a source folder.
3. Select an output CSV outside the source.
4. Review any local, network, or cloud storage warning.
5. Hash with visible progress and cancellation.
6. Resume interrupted work or finish with success, warnings, or an error.

## Manifest contract

The manifest is RFC 4180 CSV with UTF-8 BOM, CRLF endings, deterministic path order, and this fixed header:

```text
relative_path,size_bytes,file_hash,mtime_utc,source_record_id
```

`relative_path` uses `/`, excludes the selected root, and percent-encodes unsafe bytes and control characters. `file_hash` is `sha256:` plus 64 lowercase hexadecimal characters. `mtime_utc` is RFC 3339 UTC with available subsecond precision. `source_record_id` equals `relative_path`.

The manifest does not contain absolute paths, usernames, machine identifiers, file contents, accession numbers, or descriptive metadata.

## Filesystem behavior

Included entries are stable regular files beneath the selected root, including hidden and zero-byte files. Directories are traversed but receive no row. Symlinks, junctions, reparse points, sockets, devices, and other special entries are not followed and are reported.

The engine opens source files read-only. It rejects all output, checkpoint, log, and temporary paths that resolve inside the source tree. Existing output is replaced through a separate work file rather than modified through a link target.

A file is accepted only when size and modification time match before and after hashing and the byte count matches. A changing file is retried once, then omitted and reported.

## Resume

The CSV and checkpoint form the durable resume state. On resume, the engine repairs only a torn final record, re-enumerates the source, reuses a row only when path, size, and modification time match, rehashes changed files, adds new files, and removes rows for missing files. `--rehash-existing` forces full content verification.

## Outcomes

- **Success:** all eligible stable files were recorded.
- **Completed with errors:** a useful but incomplete manifest plus `_errors.log`; CLI exit `2`.
- **Interrupted:** checkpoint retained for resume; CLI exit `130`.
- **Fatal:** the run could not safely begin or continue; CLI exit `1`.

Failure to create or persist required output or error records is fatal.

## Privacy and network boundary

The product has no account, upload, telemetry, remote help, automatic update, or background service. Windows uses no browser runtime. Runtime acceptance observed no GAMI-attributed network or DNS connection in the documented scenarios. Network shares and cloud providers can communicate outside the application process tree to satisfy filesystem access.

The product does not claim an OS-enforced inability to open a network connection. Any future network feature requires a new contract and security review.

## Non-goals

Version 1 does not upload data, map accession records, edit metadata, deduplicate, rename, repair, delete, monitor folders continuously, install drivers, schedule scans, provide algorithms other than SHA-256, or promise an atomic snapshot of a collection being modified concurrently.

## Release gate

Every Windows release must pass automated tests, dependency checks, payload and installer signing, timestamp verification, immutable candidate hashing, installation and GUI smoke tests, cancellation/resume, CLI verification, and lifecycle checks. Remote and cloud acceptance must be repeated when relevant storage or engine behavior changes. Stable publication promotes the accepted candidate bytes without rebuilding them.
