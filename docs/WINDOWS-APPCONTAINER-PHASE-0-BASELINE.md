# Windows AppContainer Phase 0: frozen baseline and scenario matrix

Status: **Phase 0 contract recorded, provider coverage open** (2026-10-16).
Contract version: **windows-gui-assurance-0.1**. This is a test contract for a
successor GUI, not a claim that the current release satisfies it. The exact
supported-provider list remains provisional until institutions name and test
their providers. Phase 1 must not treat a proposed scenario as a passed one.

## Signed v1.5.0 baseline

| Item | Frozen identity or finding |
| --- | --- |
| Source tag and commit | `v1.5.0`, `8d5062ec62c18f2b4605522269b870412522ca57` in the [VM report](evidence/2026-10-16-windows-v1.5.0/README.md) |
| Signed installer | `gami-hash-windows-amd64-installer.exe`, SHA-256 `ae0fb30322f923c63d55c43ee3e531be4f7114ae0cb911ed6524bdb0fedea308` |
| Signature observation | Authenticode `Valid`, Authentic Memory signer, Microsoft timestamp; [captured signature](evidence/2026-10-16-windows-v1.5.0/installer-signature.json) |
| Tested VM | Windows 11 Pro build 26300, VMware; WebView2 Evergreen `155.0.4283.60` already installed; test account had administrator rights |
| WebView2 absent | **NOT TESTED**. Removal attempt left runtime installed. NSIS inspection is a predicted branch, not runtime evidence. |
| Network | **FAIL** for no independent internet use: WebView2 children made external connections. The [follow-up](evidence/2026-10-16-windows-v1.5.0/followup/README.md) attributed 13 HTTP requests. |

The current checkout contains a different, **unsigned** installer at
`build/bin/Authentic Memory Hashing Tool-amd64-installer.exe` (SHA-256
`d4af48f49eb81bfd679e1cf43af9bd4946b83875ced48f3e5c1d58c3e068dfeb`).
It is not the signed baseline and must not be used to reproduce v1.5.0 claims.
Existing evidence under `docs/evidence/2026-10-16-windows-v1.5.0/` is retained
read-only; new candidate evidence needs a new directory and artifact hash.

## GUI behavior contract

Status below distinguishes a source/code contract from an observed signed-GUI
result. Preserve the behavior in the successor and run the acceptance case.

| ID | Behavior to retain | v1.5.0 observation | Successor acceptance test |
| --- | --- | --- | --- |
| G01 | Pick a local collection, choose a CSV outside it, hash all eligible regular files recursively | **PASS**, 514 files in the VM fixture | Compare every CSV path, byte count and SHA-256 to independent source inventory; no missing or duplicate rows. |
| G02 | Show scan/hash phase, file and byte counts, elapsed time and responsive Cancel | **PARTIAL**: completion and Cancel observed; individual progress fields not measured | Capture UI at scan, mid-hash and completion; counts increase and Cancel responds during a large file. |
| G03 | Report skipped links/special names, unreadable files and an error log without claiming complete coverage | **NOT TESTED** in the signed GUI fixture | Inject one safe link and one denied/unavailable file; verify visible count and log path, CSV omission, and no out-of-root traversal. |
| G04 | Cancel and choose Continue now | **PASS**, 514-row resumed CSV identical to stable CSV | Cancel mid-run; checkpoint remains, resume completes, output rows match fresh run. |
| G05 | Close/reopen after an interrupted run and offer resume | **NOT TESTED** in the signed GUI fixture | Cancel, exit, relaunch as same standard user; verify offer and output match. Repeat after forced termination. |
| G06 | Detect a checkpoint from a different or moved root and require explicit choice | **NOT TESTED** in the signed GUI fixture | Resume against copied/moved root; no silent mixing. Confirm only when same collection identity is established; changed collection must require fresh output. |
| G07 | Reject output inside source, including aliases, before creating output or checkpoint | **NOT TESTED** in the signed GUI fixture | Try direct child, junction/alias and canonical equivalent; assert rejection and no new source entries. |
| G08 | Explain fatal output or provider errors; preserve valid partial progress without presenting it as Done | **NOT TESTED** in the signed GUI fixture | Revoke output access or disconnect during run; show error and recoverable state or explicit failure. |
| G09 | Write the fixed five-column CSV: `relative_path,size_bytes,file_hash,mtime_utc,source_record_id` | **PASS**, 514-row fixture | Verify header/order, `sha256:` format, UTC mtime, source record ID, and import compatibility. |
| G10 | No app-owned independent network access | **FAIL**, WebView2 tree connected externally | Prove all GUI/worker tokens lack network capability; failed socket negative controls plus process/network capture for each scenario. |
| G11 | Do not modify selected source files | **PASS for observed operations only**; no write-like source access in this VM run | Compare before/after content and metadata; capture requested access. A categorical *cannot modify* claim additionally requires an OS-enforced write-denial test. |

G02/G03/G05-G08 are implemented or described in current code and the
[Windows acceptance guide](WINDOWS-ACCEPTANCE.md), but have no complete
signed-GUI observation in the retained VM run. That distinction is deliberate.

## Frozen fixture set

| Fixture | Reproduction and oracle | Scope |
| --- | --- | --- |
| F01: signed GUI large local run | Existing [fixture recipe](evidence/2026-10-16-windows-v1.5.0/create-fixture.ps1), [fixture metadata](evidence/2026-10-16-windows-v1.5.0/fixture.json), [stable.csv](evidence/2026-10-16-windows-v1.5.0/stable.csv), [resumed.csv](evidence/2026-10-16-windows-v1.5.0/resumed.csv), and independent [verification](evidence/2026-10-16-windows-v1.5.0/stable-verification.json). | 514 files, 2,181,038,118 bytes. Stable and resumed manifest SHA-256 both `4b18e5080b9b6bf9562febc2cdeaa292acf9858fd5f7e79fe4bf31a6762188cb`. Existing CSV has captured timestamps, so regenerating source bytes later does not imply byte-identical CSV. |
| F02: compact local parity | Run [create-local-fixture.ps1](fixtures/windows-phase0/create-local-fixture.ps1) with a **new** directory; it makes five deterministic files, a sibling output folder, a copied moved-root candidate, and `expected.json` from independent SHA-256 reads. | Empty, duplicate, binary, nested and Unicode names; output-outside-source, alias, move, failure and resume tests. The fixture does not itself prove GUI behavior. |
| F03: storage-provider copy | Copy F02's `source` to each candidate provider and create a separate destination there; inventory source hashes **before** hashing and after any hydration. | SMB, cloud online-only/cached, removable, and local-to-remote or remote-to-local pairings. Capture provider version and placeholder state. Do not treat a cloud copy as byte-identical until verified. |

Example F02 creation, using a unique disposable location:

```powershell
.\docs\fixtures\windows-phase0\create-local-fixture.ps1 -Directory "$env:TEMP\GamiPhase0-$([guid]::NewGuid().ToString('N'))"
```

Use `expected.json` to compare **content/path/size**. CSV `mtime_utc` is a
separate assertion. For interruption, use the large F01 recipe or an enlarged
copy of F02 so Cancel can occur before completion. Record exact source/output,
provider state, artifact hash, account privileges, and whether output already
existed. Never reuse the same output file across unrelated cases.

## Provider and destination matrix

Every row runs on both Windows 10 and 11 with a **standard user** and the same
signed candidate. The primary matrix uses an online test network where needed;
repeat local cases with network disconnected. A fixture must be a disposable
copy, not an institution's only copy. `P` means proposed, **not supported or
passed**. `R` means a provider and tenant must be supplied by an institution.

| ID | Source | Destination | Key variant | State |
| --- | --- | --- | --- | --- |
| S01 | Local NTFS | Local NTFS sibling | Offline and online, small/large, standard user | P |
| S02 | Removable NTFS or exFAT | Local NTFS | Drive letter change, read-only media | P |
| S03 | Local NTFS | Removable NTFS or exFAT | Eject/full/denied destination | P |
| S04 | Authenticated UNC SMB share | Local NTFS | Nested tree, disconnected/reconnected share | P |
| S05 | Mapped SMB drive | Local NTFS | Same share as S04, remap identity | P |
| S06 | DFS namespace target | Local NTFS | Referral change and unavailable target | P |
| S07 | Local NTFS | Authenticated UNC/mapped/DFS SMB | CSV, checkpoint and error-log writes; permission loss | P |
| S08 | OneDrive or SharePoint sync root | Local NTFS | Cached files and online-only placeholders, successful hydration | P |
| S09 | Local NTFS | OneDrive or SharePoint sync root | CSV/checkpoint/error-log sync, account offline/revoked | P |
| S10 | OneDrive or SharePoint sync root | SMB destination | Both endpoints remote; one consent decision names both | P |
| S11 | SMB share | OneDrive or SharePoint sync root | Both endpoints remote; resume after provider interruption | P |
| S12 | Institution-requested third-party cloud provider | Local and provider destinations | Provider/version/tenant to be named before support claim | R |
| S13 | Local NTFS | Local NTFS **inside selected source** | Direct and aliased destination rejected before creation | P |
| S14 | Local NTFS | Unknown/opaque provider | Unknown classification and explicit approval/reselect | P |

For **every** applicable matrix row, record these checks:

1. Picker selection, classification reason, and consent outcome for **both**
   paths. Local-local proceeds without remote notice; detected remote and
   unknown states require the stated approval before preflight/hash/output.
2. Enumerate whole tree; match source inventory hashes, sizes and paths against
   the five-column CSV. Check online-only hydration, skipped entries, errors,
   duplicate rows, and no silently missing eligible files.
3. Cancel, close/reopen and resume; compare against a fresh run. On change,
   disconnection, remap or revoked access, stop with an accurate message.
4. Confirm app-owned process tokens and children have no network capability;
   run direct TCP/UDP/DNS/loopback/private-network negative controls, then
   correlate process events with packet traces. Attribute OS SMB/sync-provider
   traffic separately. Do not interpret background Windows traffic as GAMI.
5. Capture source requested-access operations and before/after hashes. To
   claim *cannot modify*, execute a denied-write negative control using the
   actual selected access path. Report any provider metadata/hydration effects.

## Support list and gate

Version `windows-gui-assurance-0.1` has **zero certified AppContainer GUI
scenarios**. S01-S14 are test targets. No third-party cloud provider has yet
been named by an institution, so S12 cannot be marked supported. S01/S04/S08
and matching output classes are the Phase 1 feasibility minimum; the full
matrix is the later release qualification target. Windows 10/11 support is
conditional on a signed candidate passing on each OS, under a standard-user
account. Unsupported variants must be named in release notes rather than
folded into "any source".

Phase 0 is ready for Phase 1 when the feature IDs, fixture oracles, candidate
provider list, and per-claim acceptance methods above are reviewed. A passing
runtime result, AppContainer feasibility, WebView2 absence, and actual support
for remote/cloud storage remain future gates. Never transfer the v1.5.0
network or source-access observation to a replacement build.
