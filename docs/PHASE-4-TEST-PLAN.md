# Phase 4: Safety and Correctness Test Plan

Status: **IN PROGRESS**

Recorded evidence:

- [Windows file-count scale, including 5,000,000 files](evidence/2026-09-07-windows-file-count-scale.md)

The test suite is release evidence. Cross-compilation, WSL, and simulated I/O
do not count as native operating-system acceptance tests.

## Test tiers

### Tier 1: fast automated tests

Run on every change:

```powershell
go test -count=1 ./...
go test -race -count=1 ./internal/engine/...
```

This tier covers ordinary hashing, empty folders, zero-byte files, Unicode,
CSV-special names where the host permits them, deterministic worker behavior,
source-tree immutability, changing/deleted files, links and junctions, resume,
torn tails, cancellation, process kill, and an independent digest comparison.

### Tier 2: opt-in stress tests

These must never run accidentally. Start with 10,000 files, then 100,000,
1,000,000, and finally 5,000,000:

```powershell
$env:GAMI_STRESS_FILE_COUNT = '10000'
$env:GAMI_RUN_STRESS = 'I_UNDERSTAND'
go test -run '^TestPhase4OptInFileCountScale$' -count=1 -timeout=24h ./internal/engine
Remove-Item Env:GAMI_STRESS_FILE_COUNT
Remove-Item Env:GAMI_RUN_STRESS
```

Use an internal NTFS test volume, not the USB drive. Record wall time, peak
working set, free disk before/after, filesystem, Go version, and commit ID.

### Tier 3: guarded fault and removable-media tests

Use a disposable VHDX for disk-full tests. Use the 14 GB USB only for:

- source disconnection;
- output disconnection;
- read-only source tests;
- resume after reconnection;
- an 8-12 GB representative large file;
- NTFS/exFAT behavior where relevant.

The future hardware script must require both an explicit absolute target and a
separate destructive-test opt-in token. It must reject system, repository, and
source-volume roots. Until those guards exist, USB tests are manual only.

### Tier 4: native platform and release-candidate tests

Run Tier 1 on Windows 10/11 x86-64, Windows 11 ARM64, Ubuntu 24.04 x86-64,
and both supported macOS architectures. Run installer, WebView, package,
network-share, external-drive, disk-full, and disconnect acceptance tests on
representative native systems before approving a release candidate.

## Multi-terabyte evidence

Do not claim that sparse capacity equals bytes hashed. SHA-256 must process
every logical byte. Multi-terabyte evidence is split into:

1. real hashing of representative large files;
2. synthetic metadata tests for multi-terabyte sizes and integer boundaries;
3. generated-stream tests for bounded memory;
4. modest sparse-file filesystem tests;
5. documented throughput extrapolation, explicitly labelled as extrapolation.

## Gate

Phase 4 remains open until every required test has a recorded pass on each
applicable supported operating system. Skips are visible gaps, not passes.
