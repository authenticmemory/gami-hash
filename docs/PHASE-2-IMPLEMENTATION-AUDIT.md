# GAMI Hashing Tool: Implementation Audit

## 1. Executive conclusion

The existing implementation is a useful prototype with a sensible core
structure, deterministic intent, streaming SHA-256, cancellation, checkpoint
recovery, and meaningful tests. It is not compliant with the approved version
1 product contract and must not be released to partner institutions in its
current form.

No code path was found that intentionally writes into the selected source
tree. However, the current path-safety enforcement is lexical rather than
filesystem-resolved, and an existing output file is opened with truncation.
Consequently, a symlinked output directory or an output file that is a hard
link/symlink to a source file can cause source data to be overwritten. This is
a release-blocking violation of the primary safety guarantee.

The implementation also has release-blocking manifest-integrity problems:
resume can retain stale or deleted rows, files changing during hashing are not
detected, encoded path collisions are possible, and failures to write the
error log are silently discarded.

The correct disposition is to retain the useful engine structure and tests,
then remediate the findings in Phase 3. A rewrite is neither required nor a
substitute for fixing and testing these specific failure modes.

## 2. Audit method and limitations

The audit inspected all repository-controlled source files, tests, build
scripts, and user/IT documentation. It traced filesystem mutation sites,
resume behavior, traversal, hashing, ordered writing, cancellation, GUI/CLI
entry points, and release claims.

This was a static audit. Tests could not be executed in the audit environment
because the Go toolchain is not installed. The repository also contains no
CI workflow, packaged release artifact, Windows signing configuration, Wails
frontend, or software bill of materials to execute or inspect. Claims about
runtime behavior, transitive dependencies, reproducibility, and packaged
network activity therefore remain unverified even where the source appears
consistent with them.

Severity meanings:

| Severity | Meaning |
|---|---|
| Critical | Can violate source-data safety or the central trust guarantee; blocks every release |
| High | Can produce an incorrect/incomplete manifest without adequate detection, or make recovery unsafe; blocks production |
| Medium | Contract violation, misleading reporting, scalability/reliability weakness, or incomplete validation |
| Low | Maintainability, wording, or minor interface mismatch |

## 3. Findings

### GH-AUD-001: Output aliases can overwrite source data

**Severity:** Critical  
**Contract:** Sections 11 and 17  
**Evidence:** `internal/engine/engine.go:232-252`, `:289`; `internal/ui/ui.go:140-168`, `:271-279`

The engine converts paths to absolute cleaned strings and checks whether the
output string begins with the root string. It does not resolve symlinks,
junctions, reparse points, or filesystem identity. It then calls `os.Create`
on a fresh output, which truncates an existing target.

Unsafe cases include:

- An apparently external output directory that is a symlink/junction into the
  source tree.
- An existing output path that is a symlink to a source file.
- An existing output path outside the tree that is a hard link to a source
  file. Canonical path resolution alone does not detect this case.

In the latter two cases, selecting/overwriting the output can truncate an
archival source file. The GUI duplicates the same lexical check, but engine
safety cannot depend on UI validation.

**Required disposition:** Fix in Phase 3. Never truncate an existing final
path directly. Resolve the root and output parent through platform-appropriate
canonical APIs; create a new tool-owned temporary file with exclusive-create
semantics outside the resolved root; finalize via safe replacement of the
external directory entry. Add symlink, junction/reparse-point, and hard-link
tests on supported platforms.

### GH-AUD-002: Resume accepts stale hashes solely by relative path

**Severity:** High  
**Contract:** Section 8  
**Evidence:** `internal/engine/csv.go:61-92`; `internal/engine/engine.go:277-283`, `:395-400`

Resume loads only `relative_path` values into a set. If a file is modified
between runs but retains the same path, its prior row is accepted without
comparing size or modification time. The resulting manifest may contain a hash
that no longer describes the file.

**Required disposition:** Fix in Phase 3. Parse and validate the completed row
metadata, reuse only matching path + size + precise mtime, and implement
`--rehash-existing`.

### GH-AUD-003: Deleted files remain in a resumed manifest

**Severity:** High  
**Contract:** Section 8  
**Evidence:** `internal/engine/engine.go:273-287`, `:393-407`

Resume appends to the existing CSV and never removes rows whose files no
longer exist. The completed output therefore represents a mixture of the old
and current trees rather than the collection observed by the finishing run.

**Required disposition:** Fix in Phase 3. Build/finalize a new manifest from
the current enumeration, copying validated reusable rows and omitting absent
paths, then atomically replace the prior partial manifest.

### GH-AUD-004: Files changing during hashing are accepted

**Severity:** High  
**Contract:** Section 7  
**Evidence:** `internal/engine/engine.go:395-404`, `:563-572`, `:591-617`, `:641-647`

Size and mtime are captured during directory traversal. The engine later opens
and reads the file but does not compare metadata before and after hashing. It
uses the number of bytes actually read as output size while retaining the
earlier mtime. A growing, shrinking, replaced, or concurrently written file can
therefore receive a row with inconsistent metadata and an unstable hash.

**Required disposition:** Fix in Phase 3. Stat the opened file before and after
hashing, require stable size/mtime and byte count, retry once, then report an
error. Prefer metadata obtained from the open handle where supported to reduce
path-replacement races.

### GH-AUD-005: Error-log failures are silently ignored

**Severity:** High  
**Contract:** Sections 9 and 10  
**Evidence:** `internal/engine/engine.go:686-700`

Failure to open the error log returns silently. Errors returned by
`WriteString`, flush/sync, and close are not checked. The program can therefore
finish with missing files while failing to produce the promised record of what
was omitted.

**Required disposition:** Fix in Phase 3. Make logging return errors through a
run-level fatal channel/state; check create, write, sync, and close results.

### GH-AUD-006: Path encoding is not injective and collisions are undetected

**Severity:** High  
**Contract:** Section 5  
**Evidence:** `internal/engine/engine.go:491-505`, `:717-737`

Invalid/control bytes are encoded as `%XX`, but literal percent signs are not
encoded. On a filesystem that permits raw invalid UTF-8/control bytes, a raw
name and a literal text name can map to the same manifest path—for example a
raw byte `FF` and the literal characters `%FF`. No collision detection exists.

Resume also stores these paths in a set, which compounds the ambiguity.

**Required disposition:** Fix in Phase 3. Encode literal `%` as `%25` and
reject any remaining encoded-path collision. Add round-trip and collision
tests.

### GH-AUD-007: Mid-file CSV corruption is silently treated as a torn tail

**Severity:** High  
**Contract:** Section 8  
**Evidence:** `internal/engine/csv.go:15-58`, `:95-128`

`repairTruncatedTail` truncates from the first invalid CSV record regardless of
whether corruption is confined to the physical final record. Valid records
after a damaged middle record can be silently discarded and re-hashed, while
the actual corruption is not reported as fatal. `countValidRows` similarly
treats any parse error as a tolerable tail.

Re-hashing discarded rows is safer than accepting them, but silently rewriting
arbitrary corruption violates the approved recovery contract and masks storage
damage.

**Required disposition:** Fix in Phase 3. Repair only a demonstrably incomplete
final physical record. Treat earlier corruption as a fatal incompatible or
damaged manifest.

### GH-AUD-008: Checkpoint compatibility fields are written but not validated

**Severity:** Medium  
**Contract:** Section 8  
**Evidence:** `internal/engine/engine.go:111-117`, `:129-151`, `:310-323`

The checkpoint records tool version and CSV header, but `CheckResume` validates
neither. It also does not record the output path or a distinct manifest-format
version. A checkpoint from an incompatible implementation could be accepted if
the CSV happens to parse with the current five-field header.

**Required disposition:** Fix in Phase 3. Introduce a stable format version and
validate all contract-required identity fields before modifying any artifact.

### GH-AUD-009: Fresh runs append to stale error logs

**Severity:** Medium  
**Contract:** Sections 8 and 10  
**Evidence:** `internal/engine/engine.go:288-307`, `:690-700`

A fresh manifest is truncated, but its prior `_errors.log` is opened with
append mode and never cleared. Old errors can be presented as if they occurred
in the new run. A clean fresh run can also leave a stale error log beside it.

**Required disposition:** Fix in Phase 3. Create per-run temporary log output
and replace/remove the final error log according to the current result.

### GH-AUD-010: CSV durability errors can be missed at final close

**Severity:** Medium  
**Contract:** Sections 8 and 9  
**Evidence:** `internal/engine/engine.go:308`, `:424-438`; `internal/engine/csv.go:19-58`

The engine calls `Sync`, which is good, but deferred CSV close errors are
ignored. Checkpoint removal occurs before the deferred close. The error-log
close is also ignored. Certain delayed filesystem failures can therefore occur
after the run has been classified successful and its checkpoint removed.

**Required disposition:** Fix in Phase 3. Explicitly flush, sync, close, and
check all durable artifacts before removing the checkpoint and reporting
success.

### GH-AUD-011: Ordered parallel writer has unbounded pending memory

**Severity:** Medium  
**Contract:** Section 14  
**Evidence:** `internal/engine/engine.go:354-355`, `:620-683`

Job and result channels are bounded, but the writer continuously drains
out-of-order outcomes into an unbounded map. If an early index is a very large
or slow file while another worker completes many later small files, the map can
grow with the number and aggregate path metadata of those later results.

The resume `skip` map also holds every completed relative path in memory. At
the approved five-million-file validation target, the 512 MiB memory target is
not credible without measurement or a different index strategy.

**Required disposition:** Fix or prove within limits in Phase 3/4. Bound the
reorder window/backpressure and design a measured resume index strategy.

### GH-AUD-012: Manifest ordering differs from the approved ordering

**Severity:** Medium  
**Contract:** Section 5  
**Evidence:** `internal/engine/engine.go:456-536`

Traversal sorts raw names separately within each directory and emits via
depth-first traversal. That is deterministic, but it is not necessarily global
lexicographic ordering by encoded relative-path UTF-8 bytes. Encoding can alter
sort order, and component-wise depth-first order can differ around punctuation
and directory/file prefixes.

**Required disposition:** Reconcile in Phase 3. Either implement the approved
order within the memory limits or amend the contract explicitly before coding.

### GH-AUD-013: Modification times lose sub-second precision

**Severity:** Medium  
**Contract:** Sections 6 and 8  
**Evidence:** `internal/engine/engine.go:646`; `reference/Get-FileHashes.ps1:42`

Both implementations format timestamps to whole seconds. The approved contract
requires available sub-second precision, which is also important for resume
validation.

**Required disposition:** Fix in Phase 3 and update the independent reference
script and compatibility tests together.

### GH-AUD-014: Error log lacks severity and reason codes

**Severity:** Medium  
**Contract:** Section 10  
**Evidence:** `internal/engine/engine.go:698-700`

The current tab-separated line contains timestamp, quoted path, and free-form
message only. It cannot reliably distinguish warning from processing error or
support stable automated interpretation.

**Required disposition:** Implement the approved log schema in Phase 3.

### GH-AUD-015: GUI does not disclose warning-only special entries

**Severity:** Medium  
**Contract:** Sections 4 and 9  
**Evidence:** `internal/ui/ui.go:102-123`; `cli.go:137-144`

The CLI mentions skipped non-regular entries, but the GUI appends an error-log
notice only when `FilesFailed > 0`. A run containing only skipped symlinks or
special entries creates a log without telling the GUI user.

**Required disposition:** The Wails result model and interim GUI must report
warning and error counts separately.

### GH-AUD-016: CLI does not implement the approved interface

**Severity:** Medium  
**Contract:** Section 13  
**Evidence:** `cli.go:25-62`

The current CLI documents single-dash Go flags, has no `--rehash-existing`, and
does not explicitly define `--help` as the canonical interface. Go's flag
parser may accept double dashes, but the documented contract is not present.
Worker values above 64 are accepted through the CLI even though the environment
override enforces 1–64.

**Required disposition:** Implement and test the approved CLI contract in
Phase 3 while retaining temporary aliases if desired.

### GH-AUD-017: GUI worker count can be changed through the environment

**Severity:** Medium  
**Contract:** Section 14  
**Evidence:** `main.go:25`, `:28-38`

`GAMI_HASH_WORKERS` changes GUI concurrency up to 64. The contract freezes the
version 1 GUI at two workers so non-technical runs cannot accidentally overload
an HDD or network share through inherited environment configuration.

**Required disposition:** Limit GUI startup to two workers. Keep explicit CLI
tuning.

### GH-AUD-018: The approved Wails boundary and production WebView controls do not exist

**Severity:** Medium  
**Contract:** Sections 3 and 15  
**Evidence:** `internal/ui/ui.go`; `go.mod`

The current GUI is a native-dialog/Zenity wizard. There is no Wails dependency,
TypeScript frontend, narrow engine bridge, embedded asset policy, or production
WebView hardening. Linux currently depends on `zenity`, not the approved
GTK/WebKitGTK package policy.

**Required disposition:** Expected future work. Do not begin it until the
critical engine remediations and their tests are in place.

### GH-AUD-019: Platform support and packaging are claims, not demonstrated releases

**Severity:** Medium  
**Contract:** Sections 2, 15, and 17  
**Evidence:** `build.sh`; absence of CI/release workflows and signing config

The shell script cross-compiles multiple artifacts, but the repository has no
platform test matrix, Windows signing, macOS notarization, Ubuntu package,
WebKit dependency declaration, or clean-machine verification. The build script
also removes `dist` recursively and relies on host `tar`, `gzip`, `zip`,
`sha256sum`, and Git behavior.

**Required disposition:** Phase 6/8 work. Until validated, only source-level
platform intent exists.

### GH-AUD-020: Reproducibility and CI documentation overstate the repository

**Severity:** Medium  
**Contract:** Release evidence requirement  
**Evidence:** `README.md`; `VERIFY.md`; absence of `.github/workflows/release.yml`

`VERIFY.md` states that a release CI workflow performs double builds from two
directories, but no such workflow is present. The claim that archives are
bit-for-bit reproducible across machines is not established by the repository;
archive tooling and metadata can vary. No artifact was available for an
independent rebuild comparison.

**Required disposition:** Correct the documentation now or add and demonstrate
the claimed pipeline before release. Reproducibility must be measured per
artifact, not inferred from flags.

### GH-AUD-021: Zero-network claim is plausible in direct code but unverified

**Severity:** Medium  
**Contract:** Section 12  
**Evidence:** direct Go imports; `go.mod`; `internal/ui/ui.go:127-137`

No direct application source imports an HTTP/network API. The GUI launches the
local file manager only. However, transitive dependencies were not enumerated
with `go list -deps`, the packaged executable was not inspected, and no runtime
firewall test was possible. The documentation currently states the stronger
conclusion as proven fact.

**Required disposition:** Add dependency-policy checks and packaged-artifact
network tests. With Wails, also block remote navigation and ensure all assets
are embedded.

### GH-AUD-022: Test coverage is useful but below the approved safety gate

**Severity:** Medium  
**Contract:** Sections 7–17  
**Evidence:** `internal/engine/engine_test.go`; `test/integration_test.sh`; `test/gui_test.sh`

Existing tests cover basic hashing, unusual names, invalid UTF-8, deterministic
worker output, permissions, symlink skipping, lexical output containment,
read-only traversal, cancellation, resume, torn tail, large-file streaming,
and GUI flows. These are worth retaining.

Missing or insufficient tests include:

- Output symlink/junction/hard-link attacks
- Source replacement races and files modified while hashing
- Changed/deleted files across resume
- Percent-encoding collisions and round trips
- Error-log create/write/sync/close failures
- Output disk full and disconnected output/source drives
- Mid-file CSV corruption versus torn final record
- Checkpoint version/schema incompatibility
- Five-million-file memory behavior and bounded reordering
- Windows long paths, UNC shares, junctions, and cancellation
- Windows ARM64, macOS, and Ubuntu packaged artifacts
- WebView remote-navigation and zero-network runtime checks
- GUI accessibility and non-technical usability

The integration and GUI scripts are Bash/Linux-oriented and do not constitute
the Tier 1 Windows release gate.

**Required disposition:** Expand in Phase 3 alongside fixes, then complete the
cross-platform destructive-failure matrix in Phase 4.

### GH-AUD-023: Documentation contains contract-incompatible assurances

**Severity:** Low  
**Contract:** Entire approved contract  
**Evidence:** `README.md`; `docs/WHAT-THIS-TOOL-DOES.md`; `docs/ARCHIVIST-GUIDE.md`

Examples include unconditional statements that users "cannot damage anything,"
that the tool writes exactly one CSV while it also writes sidecars/config
state, that no network stack is linked without current build evidence, and
that cross-platform binaries are reproducible without a demonstrated workflow.

The sleep wording also says a run "continues afterwards," which is normally
true after wake but should not imply progress while the machine is asleep.

**Required disposition:** Rewrite documentation after engine behavior is
finalized. Trust language must describe verified boundaries and residual risks,
not absolute reassurance unsupported by implementation.

## 4. Contract compliance matrix

| Contract area | Current status | Primary blockers |
|---|---|---|
| Supported platforms/artifacts | Not compliant | No approved tiered packaging, signing, notarization, Linux package, or platform matrix |
| GUI workflow | Partially compliant | Functional dialog wizard exists; approved Wails UI does not |
| Eligible filesystem entries | Partially compliant | Regular/hidden files included and links skipped; mount/reparse behavior lacks platform proof |
| Path representation | Not compliant | `%` collision, no collision detection, different ordering |
| CSV specification | Partially compliant | Header/BOM/CRLF/SHA-256 match; mtime precision differs |
| Stable-file correctness | Not compliant | No before/after stability validation or retry |
| Resume semantics | Not compliant | Path-only reuse, deleted rows retained, weak checkpoint validation, broad truncation repair |
| Final states | Partially compliant | Core states exist; warning/error separation and logging failure semantics differ |
| Error log | Not compliant | Append-only stale data, no severity/codes, write failures ignored |
| Source-tree read-only guarantee | Not compliant | Direct opens are read-only, but output alias/hard-link path can overwrite source data |
| Zero-network policy | Unverified | No direct network calls found; dependencies/artifacts/runtime not tested |
| CLI interface | Partially compliant | Core flags/exit codes exist; canonical interface and strict rehash missing |
| Performance/resource limits | Unverified/not compliant | Streaming exists; reorder/resume memory unbounded; scale targets untested |
| Wails/WebView/Linux policy | Not implemented | Current GUI uses Zenity/native dialogs |
| Version 1 non-goals | Mostly compliant | No upload/accounts/mapping/updater observed |

## 5. Positive controls worth preserving

The audit found several sound implementation choices that should be retained
or adapted:

- Source content is streamed through the standard SHA-256 implementation
  rather than loaded into memory (`engine.go:591-617`).
- Direct source-file opens request read access only (`engine.go:593`).
- Symlink/special entries are not deliberately followed during traversal
  (`engine.go:509-520`).
- Worker count defaults conservatively to two (`engine.go:53-56`).
- Parallel outcomes are intended to be emitted deterministically
  (`engine.go:620-683`).
- CSV uses the required header, UTF-8 BOM, RFC-style writer, and CRLF
  (`engine.go:293-305`, `:623-647`).
- The checkpoint exists before expensive scanning and survives cancellation
  (`engine.go:310-348`, `:428-443`).
- Final CSV data is explicitly synced before success (`engine.go:424-426`).
- Per-file read failures ordinarily do not abort traversal.
- GUI and CLI already share the same engine entry point.
- Existing tests provide a useful regression foundation rather than disposable
  generated code.

These controls reduce remediation cost, but they do not neutralize the critical
and high findings.

## 6. Result

**Gate result: FAIL for production; PASS for audit completion.**

The audit is complete enough to begin Phase 3. Production and partner pilots
remain blocked by all Critical and High findings.

### Required implementation order

1. GH-AUD-001: safe output creation/finalization and resolved containment.
2. GH-AUD-004: stable-file hashing and path-replacement detection.
3. GH-AUD-002 and GH-AUD-003: validated resume and current-tree finalization.
4. GH-AUD-005 and GH-AUD-010: durable, propagated artifact errors.
5. GH-AUD-006: injective path encoding and collision rejection.
6. GH-AUD-007 and GH-AUD-008: strict CSV/checkpoint recovery compatibility.
7. GH-AUD-009 and GH-AUD-014: per-run structured error logging.
8. GH-AUD-011 and GH-AUD-012: bounded deterministic ordering at target scale.
9. GH-AUD-013, GH-AUD-016, and GH-AUD-017: format and CLI contract alignment.
10. Update tests with every change; do not defer safety regression tests to the
    Wails phase.

Wails work should begin only after items 1–7 have executable regression tests
and the engine can run independently of all GUI code.

