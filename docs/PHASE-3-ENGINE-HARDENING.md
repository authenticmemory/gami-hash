# Phase 3: Go Engine Hardening

Status: **PASS**  
Date: 2026-09-07

## Scope and gate

Phase 3 makes `internal/engine` the trusted implementation shared by the CLI
and any future Wails interface. The package has no Wails dependency. This gate
does not approve a production release; packaging, native-platform acceptance,
large-corpus performance, and the Wails application remain later work.

## Implemented controls

- Source files are opened read-only. Hashes are accepted only when size and
  modification time are unchanged on the same open handle before and after the
  read; an unstable file is retried once and then reported as `FILE_CHANGED`.
- The source root and output directory are resolved through operating-system
  canonical paths. Outputs inside the resolved source tree are refused,
  including Windows directory junctions.
- Output replacement removes only the destination directory entry. A symlink
  or hard-link alias cannot cause a source file to be truncated.
- Manifests are built in a private working file, synced, checkpointed, and
  published at the end. Checkpoints retain the working-file location so an
  interrupted run is resumable.
- Resume validates the format version, header, root, output, row order, row
  shape, size, modification time, and hash. Deleted files disappear from the
  rebuilt manifest. `--rehash-existing` disables row reuse.
- Only an incomplete malformed final CSV record is repairable. Corruption in
  the middle of a manifest is fatal.
- Resume rows are streamed instead of retained in a full-path map. Parallel
  result reordering is bounded. Output ordering is deterministic regardless of
  worker count.
- Manifest path encoding is injective for the escape marker and rejected on
  any encoded-path collision.
- Symbolic links, Windows reparse points/junctions, directories encountered as
  entries, and other special files are omitted and reported.
- The error log records timestamp, severity, reason code, path, and message.
  Artifact creation, write, flush, sync, and close errors are fatal rather than
  silently ignored. Warning counts are returned separately from file errors.
- CSV modification times preserve available fractional-second precision.
- The CLI validates worker limits and implements `--rehash-existing`. The GUI
  cannot change worker count through an environment variable.

## Phase 2 finding disposition

| Finding | Phase 3 disposition |
|---|---|
| GH-AUD-001 through GH-AUD-017 | Remediated in the engine/interface boundary and covered by regression tests where applicable |
| GH-AUD-018 | Deferred: Wails implementation is a later phase |
| GH-AUD-019 | Deferred: signed packaging and platform release evidence are later gates |
| GH-AUD-020 | Deferred: reproducible release CI is a later gate |
| GH-AUD-021 | Partially addressed: no application source imports or calls a network API; binary/network enforcement still belongs in release validation |
| GH-AUD-022 | Engine gate addressed on Windows; native Linux/macOS execution, scale, fault injection, and acceptance testing remain required |
| GH-AUD-023 | Phase 3 documentation claims were corrected; all release documentation requires a final pre-production review |

## Verification evidence

Executed with official Go 1.27.0 on Windows:

```text
go vet ./...                                      PASS
go test -count=1 ./...                            PASS
go test -race -count=1 ./internal/engine/...      PASS
PowerShell reference script parser                PASS (0 errors)
```

The engine test package also cross-compiled with `CGO_ENABLED=0` for:

```text
linux/amd64    linux/arm64
darwin/amd64   darwin/arm64
windows/arm64
```

Cross-compilation proves build compatibility, not correct native filesystem
behavior. Linux and macOS tests must run on those operating systems before a
release candidate is approved.

## Residual risks carried into the next phase

1. The 5-million-file and 512 MiB targets are not yet demonstrated. A single
   extremely large directory may still be the memory worst case because Go's
   directory enumeration materializes that directory's entries.
2. Forced termination recovery has an automated regression test, but power
   loss, disk-full, permission changes, antivirus interference, and removable
   drive disconnection still need fault-injection testing.
3. The zero-network policy is supported by a source audit, not yet by an
   OS-level blocked-network runtime test or release-binary inspection.
4. The existing lightweight GUI is not the approved Wails product UI.

## Gate decision

**Phase 3 passes:** the hardened engine and its tests run without GUI code.
Phase 4 may begin. Production deployment and partner pilots remain blocked
until the residual validation and release gates pass.
