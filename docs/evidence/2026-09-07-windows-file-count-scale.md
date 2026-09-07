# Windows File-Count Scale Evidence

Date: 2026-09-07  
Platform: Windows x86-64  
Test: `TestPhase4OptInFileCountScale`  
Command mode: verbose, uncached (`-v -count=1`)  
Outcome: **PASS**

## Results

| Files | Corpus creation | Scan and hash | Manifest verification | Manifest size | Total test time |
|---:|---:|---:|---:|---:|---:|
| 100,000 | 17.194 s | 8.237 s | 45 ms | 12,588,980 bytes | 33.46 s |
| 1,000,000 | 4m 41.870s | 2m 3.846s | 292 ms | 125,889,485 bytes | 8m 17.09s |
| 5,000,000 | 20m 14.707s | 11m 10.264s | 1.957 s | 629,441,048 bytes | 52m 42.00s |

All generated files were zero-byte regular files, distributed in directories
of 1,000 files each. Every expected manifest row was streamed back through the
CSV parser and counted. The five-million-file run reached the product
contract's maximum file-count target.

The five-million total duration exceeds the explicitly timed creation,
scan/hash, and verification stages by approximately 21 minutes. That remainder
is consistent with Go test cleanup removing five million temporary files, but
cleanup was not separately instrumented and this is therefore an inference.

## What this proves

- The engine completed a manifest for five million files on this Windows host.
- The result contained exactly five million parseable CSV data rows.
- File-count progress and deterministic streaming completion remained usable at
  the contractual maximum.

## What this does not prove

- The 512 MiB peak-memory requirement: peak working set was not measured.
- Large-byte-volume throughput: the corpus contained zero-byte files.
- Native behavior on other Windows machines, architectures, or filesystems.
- Linux or macOS behavior.
- Source or output failure recovery during this particular stress run.

The next full-scale run must capture peak process memory, Go version, Windows
version, CPU, filesystem, free-space deltas, worker count, and cleanup time.
