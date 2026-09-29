# GAMI Hashing Tool — Version 1 Product Contract

**Status:** Approved  
**Contract version:** 1.0  
**Approved:** 2026-09-07  
**Last updated:** 2026-09-07

This document is the normative product contract for version 1 of the GAMI
Hashing Tool. It defines the supported product, its safety boundaries, output
format, and release obligations. If another document conflicts with this one,
this contract takes precedence after approval.

Version 1 has one job: read a user-selected folder tree and create a local CSV
manifest containing technical metadata and a SHA-256 checksum for every
eligible file. It does not interpret the collection or transfer its contents.

## 1. Intended users and operating model

The primary user is a non-technical employee of a partner institution. The
application therefore provides a graphical workflow. Technical users may run
the same hashing engine through a command-line interface.

The application operates locally, without an account, server connection,
installation of Go or Node.js, or administrator privileges. The source
collection may be on a local disk, removable disk, UNC/network share, or
mounted network filesystem.

The institution remains responsible for ensuring that the selected collection
is authorized for scanning and is not being deliberately modified during a
run.

## 2. Supported platforms and release artifacts

Version 1 support is divided into release tiers so that "cross-platform" does
not imply equal support where we have not performed equal testing.

### Tier 1 — fully supported

| Operating system | Architectures | Release artifact | GUI | CLI |
|---|---|---|---|---|
| Windows 10 and 11 | x86-64 | Signed portable `.exe` | Yes | Yes |

Tier 1 releases must pass the complete automated and manual release test suite
on a clean machine before publication.

### Tier 2 — supported after platform validation

| Operating system | Architectures | Release artifact | GUI | CLI |
|---|---|---|---|---|
| Windows 11 | ARM64 | Signed portable `.exe` | Yes | Yes |
| macOS 13 or later | Apple silicon | Signed and notarized `.app` in a `.dmg` | Yes | Yes |
| macOS 13 or later | x86-64 | Signed and notarized `.app` in a `.dmg` | Yes | Yes |
| Ubuntu 24.04 LTS | x86-64 | `.deb` package | Yes | Yes |

A Tier 2 artifact is published only after the same release has passed its
platform test suite. An unpublished build is not a supported release.

### Portable Linux CLI

A native x86-64 Linux CLI archive without the Wails GUI is also published. It
does not require GTK or WebKitGTK. Other Linux distributions may use this CLI,
but the version 1 GUI is supported only on the explicitly listed distribution.

ARM64 Linux GUI/CLI releases and older operating-system versions are outside
the version 1 contract. They may be evaluated later without being promised now.

## 3. User-visible workflow

The GUI contains only these product steps:

1. Explain what the tool does and does not do.
2. Select the source folder.
3. Select the output CSV location.
4. Review the selected paths and start.
5. Display counting/hashing progress and allow cancellation.
6. Display success, completion-with-errors, cancellation, or fatal failure.

The GUI may provide an "Open output folder" action. It must not provide cloud
upload, authentication, metadata mapping, accession-number mapping, collection
editing, automatic updates, telemetry, or remote help content.

## 4. Eligible filesystem entries

### Included

- Every regular file reachable beneath the selected root.
- Hidden and system-marked regular files.
- Zero-byte files.
- Files whose names contain spaces, commas, quotes, umlauts, non-Latin Unicode,
  emoji, or other names representable by the operating system.
- Long paths and UNC paths supported by the host operating system.

### Excluded

- Directories themselves; they are traversed but receive no CSV row.
- Symbolic links, junctions, reparse points, aliases, and other link-like
  entries. They are never followed, whether they point inside or outside the
  selected tree.
- Sockets, named pipes, device files, and other non-regular entries.
- The selected output CSV and its tool-owned sidecar files.

Every excluded link-like or special entry is recorded in the error log as a
warning. An unreadable directory is recorded as an error because its contents
cannot be enumerated.

The application must not cross a filesystem boundary through a link or mount
alias unintentionally. Ordinary mounted filesystems that are physically
located beneath the selected root are included unless the platform cannot
safely distinguish them from link-like entries.

## 5. Path representation

`relative_path` is relative to the selected root and uses `/` as its separator
on every operating system. It never begins with `/` and never contains the
selected root itself.

Paths are recorded as UTF-8. To keep every CSV record on one physical line and
preserve unusual Unix filenames reversibly, the path encoder applies these
rules to each raw path component:

- Literal `%` is encoded as `%25`.
- Bytes that are not valid UTF-8 are encoded as uppercase `%XX`.
- ASCII control bytes `00`–`1F` and `7F` are encoded as uppercase `%XX`.
- All other valid UTF-8 characters are preserved exactly; Unicode is not
  normalized or case-folded.

Encoding `%` prevents a literal name such as `%0A` from colliding with an
encoded newline. Two distinct source paths must never produce the same encoded
`relative_path`. If a collision is nevertheless detected, neither conflicting
entry may be silently accepted; the run completes with errors and records both
paths in the error log.

Manifest rows are ordered lexicographically by their encoded UTF-8
`relative_path` bytes. Worker count must not affect row order or content.

## 6. CSV manifest specification

The manifest is RFC 4180 CSV with:

- UTF-8 encoding;
- a UTF-8 byte-order mark (`EF BB BF`) for spreadsheet compatibility;
- CRLF record endings;
- exactly one header row;
- exactly five fields per data row;
- standard CSV quoting: fields containing commas, quotes, CR, or LF are quoted,
  and embedded quotes are doubled.

The fixed header is:

```text
relative_path,size_bytes,file_hash,mtime_utc,source_record_id
```

| Column | Contract |
|---|---|
| `relative_path` | Encoded slash-separated path relative to the selected root |
| `size_bytes` | Base-10 unsigned byte count of the stable file that was hashed |
| `file_hash` | `sha256:` followed by 64 lowercase hexadecimal characters representing SHA-256 of the complete file contents |
| `mtime_utc` | File modification time in UTC, RFC 3339 format, with available sub-second precision and `Z` suffix |
| `source_record_id` | Stable identifier required by GAMI Local; exactly equal to the encoded `relative_path` |

The manifest contains no absolute paths, usernames, machine identifiers,
accession numbers, descriptive metadata, file contents, or network
information. `source_record_id` deliberately repeats `relative_path`; GAMI
Hash cannot infer an institution's catalogue identifier, and a deterministic
path-derived identifier is preferable to an invented random value.

The schema and encoding are versioned product interfaces. They may not change
within version 1 without a documented compatibility decision and updated
reference implementation.

## 7. Stable-file correctness

For every file, the engine reads size and modification time immediately before
and immediately after hashing. A CSV row is written only when both observations
match and the number of bytes hashed equals the observed size.

If the observations differ, the engine retries the file once after other queued
work. If it changes again, the file is omitted and recorded as "changed while
hashing." A hash of a detected unstable file must never be presented as a
successful row.

This protects against ordinary concurrent modification. It cannot detect a
deliberate or unusual change that preserves both size and modification time.
Version 1 does not claim to provide a cryptographically atomic snapshot of a
live filesystem.

## 8. Resume semantics

A run is resumable when a valid checkpoint and a compatible partial manifest
exist for the selected output path.

The checkpoint records at least:

- Product/format version
- Canonical source-root identity
- Output path
- Start time
- Manifest schema identifier
- State required to validate completed rows

The CSV is the durable record of successfully written rows. It is flushed at
bounded intervals. A checkpoint is created before traversal begins and removed
only after successful finalization.

On resume:

1. Validate the checkpoint and CSV header/version.
2. Remove only a torn or incomplete final CSV record.
3. Reject corruption in an earlier record; do not silently truncate valid rows
   following arbitrary mid-file corruption.
4. Re-enumerate the source tree.
5. Reuse a completed row only when its relative path, size, and modification
   time still match the current file.
6. Re-hash files that are new or whose recorded metadata changed.
7. Do not retain rows for files that no longer exist; the completed manifest
   represents the collection observed by the finishing run.
8. Prevent duplicate relative paths.

Metadata matching makes interruption recovery practical for multi-terabyte
collections, but is not proof that unchanged metadata means unchanged content.
The UI and documentation must state that a collection should remain stable
during and between interrupted sessions. A `--rehash-existing` CLI option may
force verification of every existing row without changing the CSV schema.

If an external drive receives a different drive letter or mount point, resume
is allowed only after explicit user confirmation that it is the same source.
The engine must still validate all reusable rows as described above.

Starting fresh replaces the selected manifest and begins with a new checkpoint
and a new error log. It must not append to artifacts from an earlier run.

## 9. Errors and final states

The application has four final states:

### Completed successfully

All eligible, stable regular files were hashed and recorded. No source entry
was omitted because of an error. Warnings about intentionally excluded special
entries may exist and must be disclosed in the result screen.

### Completed with errors

Traversal reached its natural end, but one or more eligible files or
directories could not be completely processed. Examples include permission
denial, read failure, a repeatedly changing file, a vanished file, or an
unreadable directory.

The manifest remains useful but incomplete. The UI must state that files are
missing, display the count, identify the error-log path, and instruct the user
to send the log with the manifest. The CLI exits with code `2`.

Failure to create or write the error log is a fatal error, not something the
engine may silently ignore.

### Canceled/interrupted

The user canceled or the process received a supported termination signal.
Durable completed rows and the checkpoint remain available for resume. The GUI
returns to a clear resumable state. The CLI exits with code `130`.

An ungraceful process or power failure may lose work since the last successful
flush, but resume must not accept a torn CSV row as complete.

### Fatal failure

The run could not safely begin or continue—for example: invalid root,
unwritable output, unsupported manifest, checkpoint corruption, output storage
failure, or inability to record processing errors. The UI must not label the
manifest complete. The CLI exits with code `1`.

## 10. Error log

The error log is created next to the manifest only when at least one warning or
error occurs. It is UTF-8 text and contains, for each event:

- UTC timestamp
- Severity (`WARNING` or `ERROR`)
- Encoded relative path when available
- Stable machine-readable reason code
- Human-readable explanation

Raw unsafe filename bytes may be escaped in the explanation but must not make
the log invalid UTF-8. The application must check and propagate creation,
write, flush, and close failures.

## 11. Source-tree read-only guarantee

The tool never intentionally creates, modifies, renames, moves, deletes,
changes permissions on, or changes timestamps of any entry in the selected
source tree.

The guarantee is enforced by the engine:

- Source files are opened with read-only access and without requesting write,
  delete, or metadata-modification rights.
- Link-like entries are not followed.
- The canonical/resolved output CSV, checkpoint, error log, and temporary paths
  must all be outside the canonical/resolved source root.
- The engine performs the safety check; the GUI cannot override it.
- The tool must operate successfully when the source is read-only, subject to
  the user's ability to read it.

"Read-only" does not mean zero observable impact: hashing reads all file
contents and can create disk/network load, update operating-system access-time
metadata where the filesystem itself is configured to do so, or trigger
filesystem/antivirus behavior outside the application's control. Documentation
must not promise that the operating system or storage system records no access.

## 12. Zero-network policy

Production builds perform no network communication initiated by the
application:

- No telemetry, analytics, crash reporting, update checks, authentication,
  remote logging, uploads, API calls, remote fonts, remote images, CDN assets,
  or remote help pages.
- The WebView may load only frontend assets embedded in the application.
- Navigation to `http`, `https`, `ws`, `wss`, and other remote origins is
  blocked.
- The application does not start a local HTTP server in production.
- Network-related application dependencies are prohibited unless documented,
  reviewed, and technically prevented from communicating in production.

Reading files from a user-selected UNC path or mounted network filesystem is
permitted. That I/O is initiated by the operating-system filesystem client and
is the only intended network-related use. Therefore external observation may
show SMB/NFS traffic when the user explicitly scans network storage; this does
not violate the no-communication policy.

The packaged release—not only source code—must be tested under network
monitoring before publication.

## 13. CLI contract

The version 1 command is:

```text
gami-hash --root <folder> --output <manifest.csv> [options]
```

Supported options:

| Option | Meaning |
|---|---|
| `--root <folder>` | Required source root |
| `--output <file.csv>` | Required output manifest outside the source root |
| `--workers <1..64>` | Hashing worker count |
| `--fresh` | Replace prior output state and start a new run |
| `--quiet` | Suppress human progress output; fatal diagnostics remain |
| `--rehash-existing` | On resume, verify all rows again instead of trusting unchanged metadata |
| `--version` | Print version and exit |
| `--help` | Print usage and exit |

Long options are canonical. Single-dash forms may remain temporarily for
backward compatibility but are not part of the documented version 1 interface.

Default worker count is `2`. Progress is written to standard error; the
manifest is never written to standard output.

Exit codes:

| Code | Meaning |
|---:|---|
| `0` | Completed successfully, including warning-only special-entry skips |
| `1` | Fatal failure or invalid invocation |
| `2` | Completed with one or more processing errors; manifest is incomplete |
| `130` | Canceled or interrupted; resumable state retained |

## 14. Performance and resource limits

Version 1 is designed for collections up to at least:

- 4 TB total content
- 5 million regular files
- Individual files up to the host filesystem's supported size
- Paths up to the host API/filesystem limit

These are required validation targets, not hard-coded rejection thresholds.

Operational limits:

- Default hashing concurrency: 2 workers.
- Configurable CLI concurrency: 1–64 workers.
- GUI concurrency remains 2 in version 1; advanced tuning is a CLI function.
- File contents are streamed and never loaded completely into memory.
- Hash read buffer: implementation-defined between 256 KiB and 8 MiB per
  worker.
- Peak application memory target: below 256 MiB for ordinary runs and below
  512 MiB at the 5-million-file validation target.
- CPU use target: no more than the configured worker count for sustained
  hashing work, excluding short UI/runtime activity.
- Checkpoint/manifest data must be flushed at least every 2 seconds or every 64
  completed rows, whichever occurs first.
- Progress updates are throttled to no more than 10 engine events and 4 visual
  updates per second.

No fixed completion-time guarantee is made because throughput depends on the
storage medium, network, file sizes, antivirus, and host workload. The tool
must remain responsive to cancellation and must not intentionally monopolize
all logical CPUs by default.

## 15. Browser, WebView, and Linux dependency policy

The GUI uses stable Wails v2 with a TypeScript frontend and the existing Go
engine. It uses the operating system WebView rather than bundling Electron or
a private Chromium runtime.

- Windows uses Microsoft Edge WebView2. The release process must either verify
  that a supported runtime is present or provide an approved bootstrap/offline
  installation path. The hashing CLI must work without initializing WebView2.
- macOS uses the system WebKit supplied by macOS.
- The supported Ubuntu GUI uses GTK 3 and a compatible WebKitGTK runtime. The
  `.deb` declares exact runtime dependencies. Installing those packages may
  require administrator approval.
- Linux systems without compatible WebKitGTK use the portable CLI artifact.

Frontend assets are compiled and embedded in the application. Node.js, npm,
Go, and the Wails build tools are build-time dependencies only and are not
required on an institution's machine.

WebView developer tools, remote navigation, arbitrary script evaluation, file
URL access outside required embedded assets, and new-window creation are
disabled in production where the platform permits.

## 16. Version 1 non-goals

Version 1 does not:

- Upload files or manifests
- Connect to the GAMI platform
- Require a GAMI account
- Map files to accession numbers
- Read or modify descriptive archival metadata
- Deduplicate files
- Rename, reorganize, quarantine, repair, or delete files
- Follow symlinks or junctions
- Monitor folders continuously
- Run as a background service
- Install drivers or modify the registry for hashing purposes
- Automatically update itself
- Schedule recurring scans
- Provide hash algorithms other than SHA-256
- Guarantee an atomic snapshot of a collection being concurrently modified
- Guarantee operation on unlisted operating systems or Linux distributions

Features outside this list require a later product contract; they must not be
added opportunistically to version 1.

## 17. Release gate and approval

Phase 1 is complete when the responsible representatives approve this document
and resolve every item below. After approval, changes require an explicit
contract amendment rather than an informal implementation decision.

### Decisions requiring confirmation

- [x] Tier 1 and Tier 2 platform/architecture list is accepted.
- [x] Ubuntu 24.04 is the only supported version 1 Linux GUI target.
- [x] Five million files and the stated memory limits are accepted validation
      targets.
- [x] Modification time includes available sub-second precision, even though
      this changes the existing second-precision output.
- [x] Resume may trust unchanged path + size + modification time by default,
      with `--rehash-existing` available for strict verification.
- [x] Warning-only skipped special entries produce exit code `0`; processing
      errors produce exit code `2`.
- [x] GUI worker count is fixed at 2 for version 1.
- [x] Stable Wails v2 is the approved GUI framework.

### Approvals

| Role | Name | Decision/date |
|---|---|---|
| Product owner |  |  |
| Engineering owner |  |  |
| Security/reviewer |  |  |
