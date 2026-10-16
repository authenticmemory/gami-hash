# Phase 2 storage architecture candidate

Status: **Phase 2 production integration passed its tested engineering matrix;
not a release claim**. The
[runtime probe](evidence/2026-10-16-windows-appcontainer-phase2/README.md)
proved contained Go handle transfers and complete content manifests on a
five-file local fixture, a same-VM SMB share, and a 500-file Google Drive for
desktop mount. A follow-up run read one newly uploaded file that the user
observed as online-only before the probe. It did not run the full product engine or prove safe
resume and output publication.

The production slice now implements the 1 MiB framed protocol in Go and C++,
opaque source IDs, bounded listing, duplicated read/work handles, stable
selected-folder and file identities, hard-link and reparse rejection,
contained worker launch with an explicit inherited-handle list, product-engine
execution, progress, cancellation, work publication, and existing destination
file opens. The native objects build into `GamiHashStorageBroker.lib`, and the
targeted Go suite passes. Resume still needs to consume the brokered existing
file handles, and publication must be bound against provider replacement races
before this architecture passes its gate.

## Process boundary

The packaged native GUI, native storage broker, and Go hashing worker all run
inside the same AppContainer, with no declared network capability. The GUI
holds the two picker grants. The broker reopens them from `FutureAccessList`
tokens and performs only storage operations requested by the engine. No
full-trust process receives the picked paths or file bytes.

The Go worker uses **relative source names**, never arbitrary absolute source
paths. It requests enumeration and metadata from the broker. For each file,
the broker asks the WinRT `StorageFile` for a read-only OS handle and transfers
that handle to Go. Go streams SHA-256 directly from the handle. For output, the
broker creates a file within the separately selected destination folder and
transfers a write handle. File contents need not travel through the control
channel or a whole-collection staging directory.

The probe first used inherited handles at process startup, then successfully
used `DuplicateHandle` to give an already-running contained Go child one
read-only source handle and one destination write handle in each of the
local, same-VM SMB, and Google Drive fixtures. A product
implementation still needs a versioned, bounded request/response protocol,
one handle at a time, with cancellation, error handling, and ownership rules.
The probe sent two decimal handle values through an anonymous pipe; it did not
exercise a reusable broker or multiple simultaneous requests. Do not add
socket or broad filesystem capabilities to make the broker work.

A follow-up local fixture probe sent five read-only handles sequentially to
one contained Go worker and wrote a five-column CSV through one separate
output handle. All five paths, sizes, hashes, and source record IDs matched
the independent compact fixture. The same probe produced an identical CSV on
the same-VM SMB share and a 500-row cached Google Drive CSV with zero content
mismatches against the earlier source-verified inventory. A later run added
the 1 MiB online-only Drive file; its contained child read the exact bytes
recorded before upload, and the 501-row manifest matched the 500 prior rows.
The 0.1.9.0 probe added per-file acknowledgements and used shared engine
hash/row functions, reproducing the local, same-VM SMB, and 501-file Drive
CSVs. It also passed a five-file temporary SMB share on a separate host.
Its line protocol remains experimental, and the worker does not reuse
the product engine's checkpoint/resume and error logic. It does not settle
broader SMB/DFS behavior, provider-wide hydration behavior, or output publication
semantics.

The probe's earlier depth-first traversal had an ordering defect: a folder
named `a` could emit `a/z.txt` before its sibling `a.txt`, even though the
engine's manifest order places `a.txt` first. The native probe now schedules
all pending items by full relative UTF-8 name, and the contained Go probe
rejects malformed relative names. Signed 0.1.10.0 emitted `a.txt`, `a/z.txt`,
`b.txt` in that order on a dedicated VM fixture, with three correct hashes.
Later, unsigned source changes aligned broker sorting and Go row formatting
with the engine's percent-encoding rule; those changes passed local tests but
have not yet been run as a signed VM package.
The scheduler can retain many items in memory; bounded provider paging with
stable sort order remains a product requirement.

## Adapter contract

The engine now routes its ordinary filesystem source enumeration, read-only
open, metadata check, and same-file comparison through a private
`sourceAccess` interface. It also routes output working-file creation,
sidecar writes, publication, removal, and error-log creation through a private
`destinationAccess` interface. The default OS implementations retain the
released path behavior, and the existing engine tests pass. These are refactor
seams, not a broker backend: validation, resume inspection, completed-row
reading, and the interface arguments still use ordinary OS paths. The
contained Go manifest probe calls
shared hash and row-formatting functions, but does not call `engine.Run`.

Expose two distinct interfaces to the Go engine:

| Source operations | Destination operations |
| --- | --- |
| Enumerate children in deterministic order | Create a uniquely named working file |
| Read metadata and reparse/provider state | Open existing manifest/checkpoint for resume |
| Open a file with read-only access | Flush, close, and publish a completed file |
| Compare identity before and after hashing | Replace/remove only entries in the selected destination |

The source interface has no create, write, rename, or delete method. The
broker requests only read access for source handles. The destination interface
never accepts a source-relative name. This separation makes accidental source
writes harder, but the native broker still holds the picker grant and must be
audited and traced for write attempts.

## Broker protocol to implement

The 0.1.9.0 probe adds acknowledgements to its newline frames, but it cannot
support reliable resume or per-file errors. Replace it with a versioned, bidirectional protocol
over inherited anonymous pipes. Frame each message with a 32-bit length and
enforce a 1 MiB maximum before allocation. Require a monotonically increasing
request ID and a response for every request. Reject unknown versions,
operations, duplicate IDs, malformed UTF-8, absolute paths, `.`/`..` path
segments, and names outside the selected source root.

The first implementation needs `List(folder_id)`, `Stat(item_id)`,
`OpenRead(file_id)`, `CreateWork(kind)`, `OpenWork(name)`,
`PublishWork(name, destination_name)`, `RemoveWork(name)`, and `Cancel`.
`List` returns display names and short-lived opaque IDs for broker-held WinRT
items. The Go worker uses names only for manifest rows, and IDs for later
storage requests. `List` must return bounded pages and stable ordering; it
cannot load an arbitrarily large directory into memory. `OpenRead` transfers only a read
handle; `CreateWork` transfers a write handle only for a broker-generated
entry in the independently selected destination. No request accepts an
arbitrary absolute path or asks the broker to modify the source.

Each transferred handle has one owner in the Go child, which closes it after
use. The broker retains its own handle only until duplication and records the
request ID, relative item, access mode, and result. A timeout, broken pipe,
or child exit must close remaining broker handles and leave a clearly marked
recoverable destination checkpoint. Do not report a completed manifest until
the CSV is flushed, closed, validated, and published through the destination
provider. The current probe does none of these recovery steps.

## Identity and containment gates

Before any output creation, resolve the selected source and destination to
stable storage identities and prove that the destination is outside the source.
String prefix checks are insufficient for junctions, hard links, mapped drives,
DFS aliases, cloud-provider aliases, and case differences. Use opened-handle
volume/file IDs and WinRT item equality where available; test what each
provider actually returns. If the relationship cannot be established, reject
the run and explain what the user must reselect. Never follow a source entry
that can escape the selected tree without verifying its resolved identity.

Persist the picker tokens, source identity, destination identity, and manifest
format version for resume. On reopen, verify that tokens still resolve and
that identities are compatible with the saved run. A moved-root confirmation
must be explicit. A missing share, expired grant, changed cloud item, or
ambiguous identity must not silently resume against a different collection.

Create checkpoint and CSV working files only in the selected destination.
Replace directory entries without truncating existing aliases or hard links.
Do not assume WinRT rename/replace is atomic on every SMB or cloud provider;
test crash recovery and document the supported behavior per provider.

The current native probe checks source/output containment only with a lexical
path prefix and recursively follows every `StorageFolder` returned by WinRT.
That is **not** an identity or reparse-point defense. A VM fixture proved the
failure: a junction inside the selected source targeted a separate folder,
and the signed 0.1.10.0 contained walker hashed that outside file as
`escape/outside.txt`. The fixture was confirmed as a Windows junction, and
the CSV digest matched the outside file. **The current broker fails the Phase 2
source-containment gate.** It must not be used on untrusted collections.
The released path-based engine already skips Windows
reparse entries, but that rule can also omit cloud placeholders; the contained
adapter needs to distinguish cloud tags from name-surrogate links and verify
the resulting item's identity. Microsoft documents the
[reparse tag's name-surrogate bit](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-tags)
and the [file attribute and tag query](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_attribute_tag_info).
`StorageFolder` being returned by WinRT is not evidence that an entry is an
ordinary directory. Its projected `FileAttributes` enum omits the reparse
bit; a candidate metadata route is the shell's
[`System.FileAttributes`](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-fileattributes)
property, or a raw directory handle queried with
[`FileIdExtdDirectoryInfo`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_extd_dir_info).
Neither route is accepted until it distinguishes the test junction on local
storage **and** works or fails closed on the tested SMB and cloud providers.
The signed 0.1.12.0 diagnostic tried to open the picked source through
`IStorageFolderHandleAccess` for `FileIdExtdDirectoryInfo`, but Windows denied
`Create(".")` and did not accept `Create("")`. It therefore never reached the
tag query, and its manifest still included the outside file. A shell-property
diagnostic is next; no containment decision can be based on the failed handle
route.
The signed 0.1.13.0 diagnostic retrieved `System.FileAttributes` for the
local fixture and saw `1040` on the junction and `32` on the ordinary file.
The WinRT walker still followed the junction because this was an observation,
not an enforcement build. The follow-up same-VM SMB and Google Drive tests
returned ordinary attributes on the items observed; the tested Drive control
was already hydrated, so a fresh online-only item still needs a
before-first-open test. Any missing or ambiguous attribute value must fail
closed.
The signed 0.1.14.0 guard rejected the local junction before hashing the
outside file and preserved byte-identical manifests on the known-good local,
same-VM SMB, and Google Drive fixtures. This narrows the reparse risk for
those cases, but it is not source/output identity enforcement or full provider
coverage.
A separate local output-alias fixture confirmed that the probe's lexical
source/output check permits a junction outside the source whose target is
inside it. Two CSVs were written inside the source, and the manifest included
its own partially written output. This is a source-write failure. A signed
0.1.15.0 experiment scans source-folder identities and compares each with the
selected output using WinRT `IsEqual` before creating output. Its runtime
result failed: `IsEqual` returned false for the output junction and the source
folder it targeted, and the probe again wrote inside the source. `IsEqual`
cannot be the sole containment check. A replacement must establish the
resolved destination identity before any write and preserve that binding
through output publication. Identity stability, races, and provider behavior
still need separate evidence.

The signed 0.1.16.0 probe added a conservative pre-write rule: refuse a
picker-selected output folder whose projected `System.FileAttributes` includes
the reparse-point bit. It refused the known output junction before enumeration
or output creation. The same build preserved byte-identical manifests on the
known-good local, same-VM SMB, and Google Drive fixtures. This is a validated
guard for the tested junction shape, not general destination identity. The
production design must still bind validation and publication to stable handles
and fail closed for hard links, other reparse types, DFS/provider aliases, and
replacement races.

## Integration order

1. Turn the successful one-file transfers into a bounded request loop, then
   verify a complete source tree on local, separate-host SMB, and cloud
   fixtures. Compare every file hash independently. The experimental 0.1.9.0
   signed VM test passed local, same-VM and separate-host SMB, and Google
   Drive fixtures; it is
   still a probe rather than the product storage adapter.
2. Put enumeration, metadata, read, output, rename/remove, and persistence
   behind a narrow storage interface. Keep the current OS backend for CLI and
   macOS/Linux. Refactor the engine once so CSV and resume logic are shared.
3. Compare complete manifests, errors, cancel/reopen/resume, changed/missing
   files, Unicode/long paths, provider hydration across providers, and output failure recovery
   against the frozen Phase 0 fixtures.
4. Trace source write attempts and the full process tree's network activity.
   Attribute SMB and sync-provider traffic separately. Only then advance the
   Windows GUI assurance claim.

Windows' documented handle interfaces are
[IStorageItemHandleAccess](https://learn.microsoft.com/en-us/windows/win32/api/windowsstoragecom/nn-windowsstoragecom-istorageitemhandleaccess)
and [IStorageFolderHandleAccess](https://learn.microsoft.com/en-us/windows/win32/api/windowsstoragecom/nn-windowsstoragecom-istoragefolderhandleaccess).

## Production integration outcome

The production adapter implements the bounded broker described above and keeps
the shared engine's CSV, checkpoint, cancellation, and resume behavior. It
binds source and destination decisions to opened identities, rejects source
reparse entries and source/output aliases, rejects unsafe hard-link states, and
publishes through a verified exclusive work handle with fail-if-exists rename.

Development-signed package `0.2.5.0` passed the tested Windows 11 local,
same-VM SMB, and Google Drive matrix, including restart/resume and the two known
junction attacks. Its local, SMB, and cloud manifests matched their frozen
oracles. A WPR FileIO trace found source reads and no product-tree source write
or mutation events. These results close the Phase 2 engineering gate for that
matrix. They do not expand support to untested providers, DFS variants,
Windows 10, or a release artifact; those remain later acceptance gates.
