# Phase 2 storage adapter investigation — 2026-10-16

Status: **Phase 2 product engineering gate passed for the recorded Windows 11
matrix; release acceptance remains open**.
This is a disposable Windows 11 VMware probe, not a release build or a claim
that the shipped GAMI Hash GUI has changed.

## Test artifact and boundary

- MSIX: `AuthenticMemory.GAMIHash.AppContainerProbe` version `0.1.4.0`.
- Signed test package SHA-256:
  `3dbf9ea83145955e01b07453d6a6d7fa584f4c196d2a0c7593b74ccbb1bdb48f`.
- Installed manifest SHA-256:
  `4b01c4a4eca91219f2173d201ce1b595c275be15c8db854906e7c8ab5dd558e5`.
- Installed manifest sets `uap10:TrustLevel="appContainer"` and has empty
  `Capabilities`. The interactive worker and Go child both reported
  `TokenIsAppContainer=1`; this run did not repeat packet/WFP attribution.
- The certificate is a temporary development signer trusted only in the
  disposable VM. Build outputs and private key material are ignored by Git.

## Local fixture result

The user selected the five-file local source and separate output through the
probe's folder pickers. The worker reopened the saved tokens, then called
Windows' `*FromApp` APIs and launched the bundled Go test binary as its child.
The worker reported:

```text
PID=5084 AppContainer=1
WinRT enumeration files=5 bytes=65577
Path API failed after 0 files: Access is denied.
FromApp root attributes=1 error=0
FromApp root entries=4
FromApp file read=1 bytes=1 error=0
FromApp output write=1 bytes=1 removed=1 removeError=0
Phase2 Go PID=12432 AppContainer=1
Phase2 Go exit=0 wait=0
```

The Go child's captured stdout was:

```text
FromApp Go root entries=4
FromApp Go file="duplicate.txt" bytes=13 statSize=13 sha256=0b048390db655594c0f25acf8de0975e7d8e34bc2b2550e43626d708c0ed2f21
FromApp Go output create/write/remove=ok
```

The 13-byte digest matches the independent local fixture inventory. The Go
probe used `CreateFileFromAppW` and ordinary Go reads from the returned handle;
Go's `os.File.ReadDir` enumerated from a directory handle opened with that
API. Its only file creation was an exclusive temporary file in the selected
output folder, which it deleted. No output operation targeted the source.

This shows that a contained Go worker can potentially retain incremental
hashing through AppContainer-aware file handles. It does **not** show that the
existing engine already runs in the container: its validation, enumeration,
canonicalization, checkpoint, CSV publishing, and error log still use ordinary
path APIs. Nor does this run prove anything about SMB, cloud placeholders,
source-write absence at the OS event level, or external network packets.

Probe 0.1.7.0 later repeated the local file-handle test with the Go child
already running. Both WinRT-granted handles duplicated successfully into that
AppContainer child, which exited 0. Its captured log reports the same 13-byte
hash above and a successful separate output write. The native worker reported
removing its temporary output file. This is one local file pair, not a complete
local manifest run.

## Same-VM SMB result

The user then picked `\\GAMI-HASH-VM\GamiPhase1Loopback\source` and its
separate `output` folder. The contained WinRT worker again enumerated five
files and wrote its diagnostic CSV. Ordinary C++ path traversal failed with
"Network access is denied." The AppContainer-aware path APIs also failed:

```text
WinRT enumeration files=5 bytes=65577
FromApp root attributes=0 error=65
FromApp enumerate error=65
FromApp output create error=65
Wrote diagnostic CSV=\\GAMI-HASH-VM\GamiPhase1Loopback\output\phase1-probe.csv
```

Windows error 65 is `ERROR_NETWORK_ACCESS_DENIED`. Thus the local `*FromApp`
success does **not** extend to even this same-VM SMB share. The WinRT storage
object path remains the proven route for this fixture. A genuine separate-host
SMB retest is still needed; the earlier host share was removed after Phase 1.
No Phase 2 Go child was launched for this SMB case because the disposable
0.1.4.0 harness invokes it only for the local fixture.

With probe 0.1.5.0, the same picker-selected SMB source did provide an OS
read handle from its WinRT `StorageFile` (`HRESULT=0`, first file
`duplicate.txt`). Creating a writable handle directly from the destination
`StorageFolder` returned `0x80070003` (path not found), although the WinRT
worker still wrote its CSV. The child was therefore not launched for this
SMB case. Probe 0.1.6.0 created a WinRT `StorageFile` first and requested
its write handle. Both source and output handle requests returned HRESULT 0.
The contained Go child exited 0, read all 13 bytes of `duplicate.txt`, and
wrote one byte to the destination handle. Its SHA-256,
`0b048390db655594c0f25acf8de0975e7d8e34bc2b2550e43626d708c0ed2f21`,
matched the independently generated fixture inventory. A separate VM check
found the temporary output file absent after cleanup. A post-run inventory of
all five source files matched their pretest sizes and SHA-256 hashes, with zero
mismatches. The package-local output fallback was not used.
The signed 0.1.6.0 MSIX SHA-256 was
`3e52c64d572b9567beef841214a51888394917c3a7cdb5c50260f68029678af3`.

Probe 0.1.7.0 tested the next boundary: the Go child was already running
when the native worker duplicated a picker-granted SMB source handle and a
separate SMB output handle into that process. The worker sent only the two
child-process handle values over an anonymous pipe. The child reported
`AppContainer=1` and exit code 0:

```text
Phase2 WinRT source handle HRESULT=0 file=duplicate.txt
Phase2 WinRT output file handle HRESULT=0
Phase2 dynamic Go PID=12364 AppContainer=1
Phase2 dynamic source duplicate=1 error=0 output duplicate=1 error=0
Phase2 dynamic control sent=1 bytes=4
Phase2 dynamic Go exit=0 wait=0
Phase2 WinRT output test removed=1
```

The captured Go child log says it read 13 bytes with the expected
`0b048390db655594c0f25acf8de0975e7d8e34bc2b2550e43626d708c0ed2f21`
SHA-256 and wrote one byte to the separate output handle. The digest matches
the frozen five-file fixture. The signed 0.1.7.0 MSIX SHA-256 was
`083000ea8245a6940b3e9bb31a97779d3f7d432a2c39276e5c9f005ae404dd01`.
The detailed status and child log were collected into the ignored
`build/bin/appcontainer-phase2/` directory. This proves an on-demand handle
transfer for **one** same-VM SMB file pair. It does not establish a complete
broker protocol, separate-host SMB behavior, or a network-silent product GUI.

This proves one brokered SMB file can be read by contained Go and one
separate SMB output file can be written through inherited handles. It does
not prove recursive enumeration or five-column CSV/resume parity in Go.

## Google Drive for desktop result

The user selected streamed `G:\My Drive\gami-test` and a separate streamed
destination, with Drive for desktop running. The contained worker reported:

```text
WinRT enumeration files=500 bytes=940051
Path API failed after 0 files: Access is denied.
FromApp root attributes=1 error=0
FromApp root entries=501
FromApp file read=1 bytes=1 error=0
FromApp output write=1 bytes=1 removed=1 removeError=0
Wrote diagnostic CSV=G:\My Drive\gami-test-destination\phase1-probe.csv
```

The `*FromApp` result is stronger than the SMB result for this particular
Google Drive mount, but it covers only a one-byte file read and a temporary
output write. It does not establish full Go hashing, fresh online-only
hydration, or behavior across other cloud providers.

Probe 0.1.5.0 then requested OS handles from the picker-granted `StorageFile`
and destination `StorageFolder` and inherited them into the contained Go child.
Both handle requests returned HRESULT 0. The child reported
`AppContainer=1`, exited 0, read all 2,441 bytes of `file_001.txt`, and wrote
one byte through the destination handle. Its SHA-256 was
`493b4aca28c68f3face863389ed2634c17d8307147afb558742c4ec6c18b05ca`;
an independent `Get-FileHash` in the VM returned the same digest. The native
worker removed the temporary output file. This establishes streaming of one
Google Drive test file through a brokered read-only handle to contained Go,
not complete 500-file Go manifest parity or fresh hydration.

The 0.1.5.0 signed test package SHA-256 was
`6d24127e6f9beb9ed22641acf3446f4abf3397cd6173b2d0f7b0995e3d44f3ae`.
Its temporary signing private key was removed after packaging.

Probe 0.1.7.0 also passed the on-demand handle test on this same Google Drive
mount. The worker reported successful source/output `DuplicateHandle` calls
into an already-running Go child (`AppContainer=1`, exit 0), then removed its
temporary output file. The captured child log reports a 2,441-byte read,
the same independently checked
`493b4aca28c68f3face863389ed2634c17d8307147afb558742c4ec6c18b05ca`
SHA-256, and a successful write through the destination handle. This was a
cached test file; it does not prove fresh online-only hydration.

Across the 0.1.7.0 local, same-VM SMB, and Google Drive runs, the on-demand
transfer passed for one source/output file pair per run. Each Go child was an
AppContainer process and exited 0. The package did not implement a reusable
request loop or hash the complete source collection in Go. The full Phase 2
gate remains open.

## Multi-file Go manifest probe

The signed 0.1.8.0 disposable package (SHA-256
`38177dae5f64daddb97639082fd6cf7b6e676d8276117049c419e863d92db7d8`)
introduced a sequential broker protocol. The native worker enumerated the
picker-granted local fixture, duplicated one read-only handle per file into
an already-running contained Go child, and passed each handle with its
relative name over a pipe. It gave the child a separate WinRT-granted output
handle. The worker reported `AppContainer=1`, five transferred files, and Go
exit 0. The child reported `Manifest files=5 bytes=65577` and wrote a UTF-8
BOM, CRLF, five-column CSV in the selected output folder.

The collected CSV has exactly five rows; independent comparison against the
frozen `expected.json` found **zero path, byte-count, hash, or source-record-ID
mismatches**. It includes the nested Unicode name and empty file. This is
content parity for the compact fixture, not byte-for-byte parity with the
signed GUI's 514-file baseline: the fixture's timestamps differ, and this
probe does not use the product engine's resume, warning, or error-log code.
The CSV and child log are retained in the ignored `build/bin/appcontainer-phase2/`
directory; the signed package is also in ignored build output.

The 0.1.8.0 multi-file run also completed on the picker-selected same-VM SMB
share. The contained Go child exited 0 after five transferred source handles
and reported `Manifest files=5 bytes=65577`. The copied SMB CSV passed the
same independent five-row oracle with zero mismatches and was byte-identical
to the local fixture CSV (SHA-256
`44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`).
This is a same-VM share, not a separate-host SMB or DFS validation. No
checkpoint or failure recovery was exercised.

On the streamed Google Drive for desktop mount, the same 0.1.8.0 package
transferred 500 read-only source handles to one contained Go child. It exited
0 and reported `Manifest files=500 bytes=940051`. The copied CSV has exactly
500 rows. Comparison against the earlier 500-row WinRT probe CSV, which had
been checked against independent post-run source hashes with zero mismatches,
found **zero path, size, hash, or source-record-ID mismatches**. The new CSV
SHA-256 is
`cdcaa3baa57c170e115b2f0adfb26dcfd469ffda2862d2c30b58d9ba596323d7`.
The output was written to the separate selected Google Drive destination.
These source files were already cached by earlier tests; this does not prove
first-open online-only hydration. It also does not prove that the CSV finished
uploading to Google Drive's web service in this run.

### Fresh online-only Google Drive file

On 2026-10-16, a new disposable 1,048,576-byte file was generated on the
host and uploaded through the host browser to the same Drive source. Its
pre-upload SHA-256 was
`233e72efb84d5a046de94bdab4e661b8d375335075f64f5e47048604b08a3f3c`.
The file appeared in the VM without its content being opened, and the user
reported a cloud / online-only icon in Drive for desktop before the probe.
The VM's file-existence check did not read content. The signed 0.1.8.0
AppContainer probe then ran on the selected source and destination:

```text
WinRT enumeration files=501 bytes=1988627
Phase2 dynamic Go PID=4936 AppContainer=1
Phase2 dynamic Go exit=0 wait=0
Phase2 manifest Go PID=9856 AppContainer=1
Phase2 manifest transferred files=501 Go exit=0 wait=0
```

The dynamic one-file child read the new file first, reported 1,048,576 bytes,
and calculated the exact pre-upload digest. The subsequent manifest contained
501 distinct rows and 1,988,627 total bytes. Its new row had the same size
and SHA-256; the other 500 rows had zero path, size, hash, or record-ID
mismatches against the preceding cached Drive manifest. The copied manifest
SHA-256 was
`79adafa7e9374c4a9b8ee26d866d10bd93affa6785171514579050f238f9e6d2`.
The working logs and CSV are in ignored `build/bin/appcontainer-phase2/`.
This confirms one previously online-only Drive item was successfully read
through a picker-granted handle by the contained Go process. The online-only
status is a user-observed icon, not an independent Cloud Files API trace;
provider-side downloads, uploads, and destination publication were not
attributed in this run. It does not generalize to other cloud providers.

After signing 0.1.8.0, the Go probe source was changed to call the engine's
shared `HashReader`, `ManifestHeader`, and `ManifestFields` functions. The
engine and Go probe pass their Windows tests, but these source changes are
**not** in the signed 0.1.8.0 package. They were first exercised in the
signed 0.1.9.0 local test below. The recorded 0.1.8.0 local, SMB, and Google
Drive CSVs came from the earlier probe hashing and row-formatting loop.

## Acknowledged broker protocol probe

Signed disposable package 0.1.9.0 (SHA-256
`d03cb4979b0216ea3b46a8508f9d4258115cf751c22d60c59617284a8a58c318`)
uses the shared engine `HashReader`, `ManifestHeader`, and `ManifestFields`
functions in its contained Go child. It sends a `READY` acknowledgement,
acknowledges every source file after hashing, and reports a final `DONE`
count and byte total. The native broker waits for each response before
transferring another source handle. The installed package still declares
`TrustLevel="appContainer"` and has empty `Capabilities`; this run did not
repeat process-tree packet/WFP capture.

On the five-file local fixture, the GUI and Go child both reported
`AppContainer=1`. The broker received `DONE 5 65577`, the child exited 0,
and the collected CSV passed the frozen five-row oracle with zero mismatches.
Its SHA-256,
`44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`,
is byte-identical to the earlier local and same-VM SMB 0.1.8.0 CSVs. This
checks the acknowledged protocol and shared hash/row functions on one local
fixture, not the full engine's checkpoint, error, or publication path.

The same 0.1.9.0 probe then ran on the same-VM SMB fixture. The child reported
`DONE 5 65577`, exited 0, and its CSV passed the same frozen oracle with zero
mismatches. It was byte-identical to the 0.1.9.0 local CSV (SHA-256 above).
This still does not establish separate-host SMB behavior or complete
source/output identity checks.

With the user's earlier approval, a temporary encrypted SMB share was
recreated on the separate Windows host for a 0.1.9.0 retest. The VM reached
the host at `\\192.168.247.1\GamiPhase1Remote` using a dedicated temporary
account and a firewall rule scoped to its VMnet8 IP. The contained worker
reported five files/65,577 bytes, a contained Go child, `DONE 5 65577`, and
exit 0. The resulting CSV was written to the separate host's output folder
and passed the frozen five-row oracle with zero mismatches. Its SHA-256 was
again `44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`.
An independent host source inventory had five files and 65,577 bytes both
before and after; all file sizes and SHA-256 values matched. This establishes
content preservation, not the absence of attempted source writes. After the
test, the guest stored credential was removed. The host cleanup script removed
the temporary share, firewall rule, account, and secret; a separate host
query confirmed all four were absent. The five disposable fixture files remain
in ignored build output.

The same host fixture was hashed outside AppContainer by both the current
CLI built from this worktree and the previously retained, Authenticode-valid
signed v1.5.0 CLI (binary SHA-256
`119921fa70185f18b56c138c15d69c6a15e5bdeefd8adf32e483493b247a1569`).
Each CLI exited 0 and wrote five rows. Both CSVs were byte-identical to the
contained 0.1.9.0 local, same-VM SMB, and separate-host SMB probe manifests
(SHA-256 `44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`).
This is full CSV byte parity for the five-file compact fixture, including
timestamps. It does not establish parity for resume, errors, changed files,
or a larger mixed collection.

The 0.1.9.0 probe also completed on the streamed Google Drive source with
the fresh file now present. The broker received `DONE 501 1988627`, the
contained child exited 0, and the collected 501-row CSV was byte-identical
to the independently checked 0.1.8.0 fresh-file manifest (SHA-256
`79adafa7e9374c4a9b8ee26d866d10bd93affa6785171514579050f238f9e6d2`).
This confirms the acknowledged protocol and shared engine hash/row functions
worked on this Drive mount. It does not repeat a first-open hydration test:
0.1.8.0 had already read and hydrated the fresh file.

## Open gates

1. Mature the sequential probe into a bounded multi-request broker with
   cancellation, recovery, and provider identity checks. Complete content
   manifests matched the compact local and same-VM SMB fixtures and the
   cached 500-file Google Drive inventory. Verify full engine parity and
   test provider errors and another cloud provider. One freshly uploaded
   Google Drive file passed the read/hash check described above.
2. Implement a narrow storage adapter for source read/enumerate/metadata and
   separate destination create/replace/remove operations. Bind both to the
   picker grants. Preserve stable identities and fail closed on source/output
   aliases, reparse escapes, and revoked access.
3. Compare complete five-column CSVs and resume state with the released
   engine: Unicode and long paths, unreadable/changed/missing files, cancel,
   close/reopen, moved-root confirmation, and error logs.
4. Capture attempted source writes and network traffic for the full contained
   process tree, with provider traffic identified separately.

The existing [Phase 1 decision](../../decisions/0001-windows-appcontainer-storage-adapter.md)
still applies: directly passing picker paths to ordinary Go `os.*` calls
failed. The `*FromApp` APIs are the candidate adapter, not a direct-path fix.

## Pending sorting and junction fixtures

Review found that the 0.1.9.0 native broker's depth-first walk can emit
`a/z.txt` before sibling `a.txt`. The engine requires global relative-path
order. A corrected native queue and stricter Go relative-name validation
compile and pass the Go probe tests. Signed disposable 0.1.10.0 MSIX
(SHA-256 `03f8cd8cbc0f273cb9285e730d1009de8413bc5cdb9a4e947ccea9781c2197b7`)
ran on a three-file sorting fixture in the VM. Both worker and Go child reported
`AppContainer=1`; the child reported `DONE 3 32` and exited 0. The copied CSV
has exactly `a.txt`, `a/z.txt`, `b.txt` in that order. All sizes, SHA-256 values,
and source-record IDs match independent values computed from the fixture's
three known payloads; CSV SHA-256 is
`1f758cd245785737631095b2d54512e23df26554dd9099aa35470deeac4ff0a3`.
This verifies the corrected global ordering for one deliberately adversarial
tree shape, not arbitrary provider order or large-directory memory bounds.

After 0.1.10.0 was signed, the Go child was changed to use the engine's
percent-encoding rule for manifest names, and the native broker's sort key
was aligned with it. The Go unit tests and native package compilation pass;
those later changes are **not** in the signed 0.1.10.0 VM result. A separate
disposable junction fixture then gave a decisive negative result. Its selected
`source` contains `inside.txt` and a junction named `escape` that targets a
separate `outside` folder. An independent VM inspection confirmed the
`Directory, ReparsePoint` attributes, `Junction` link type, and target path.
The signed 0.1.10.0 contained worker reported two files/53 bytes, and its
manifest contained both `inside.txt` and **`escape/outside.txt`**. The latter
row's SHA-256,
`3d7df20fe8c0166b800ebe727b1720717dca37174ad1af3e0c7b0a20e966ef94`,
matched the independently inspected file outside the selected source.
This demonstrates that the current WinRT walker **crosses a junction out of
the selected source**. The Phase 2 containment gate fails. The probe must
not be used on untrusted collections, and the product adapter needs a
fail-closed raw reparse/identity check before recursing or opening files.

A follow-up signed 0.1.12.0 diagnostic package (SHA-256
`6a73e960e022467f69b15adb2a8ecd8782e79b9081796f06851f9099666ae6fc`)
tried to open the picker-granted source as a raw directory handle so it could
query `FileIdExtdDirectoryInfo` before recursion. In the same junction fixture,
`IStorageFolderHandleAccess::Create(".")` returned HRESULT `0x80070005`
(access denied), and `Create("")` returned `0x80070003` (path not found).
The worker again reported two files/53 bytes and completed the manifest.
**This raw-directory route did not expose the junction tag and is not a fix.**
A signed 0.1.13.0 diagnostic package (SHA-256
`47cf3fbd839287633831d1bdacc4f9da11d57761c7b8032625125b1fc5612cb2`)
ran in the VM and queried `System.FileAttributes` through WinRT's
`RetrievePropertiesAsync`. It reported `1040` for the junction (`1024`
reparse-point bit plus `16` directory bit) and `32` for the ordinary file.
The worker still read both files because this package is diagnostic only.
The property can distinguish this local junction before recursion. Follow-up
runs found ordinary attributes on all four top-level same-VM SMB entries
(`16` for its nested folder, `32` for its files) and `128` on the tested
Google Drive files, including the previously hydrated control file. These
results show that the property is available on those fixtures. They do not
establish the attributes of a newly online-only cloud file before first open,
or the behavior of other providers.

The native probe now has a fail-closed `System.FileAttributes` check before
either WinRT walker processes a source item. It rejects any item whose
attributes are missing, unsupported, or marked as a reparse point. The signed
0.1.14.0 disposable package (SHA-256
`581aa40a9bc328ca7378b93e623d1ff65a8f6e4335589d4ec62bafdbb0e614bb`)
passed its first VM guard check on the junction fixture. The worker reported
`ERROR REFUSED source reparse point: escape` before any `WinRT enumeration`
completion or `Phase2 manifest` line. This is a controlled improvement over
0.1.10.0, which hashed `escape/outside.txt`. The same installed guard probe
then completed the five-file local and same-VM SMB fixtures and the 501-file
Google Drive fixture. Independently collected local and SMB CSVs were
byte-identical to the verified five-row fixture (SHA-256
`44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`).
The Drive CSV was byte-identical to the earlier independently verified
501-row manifest (SHA-256
`79adafa7e9374c4a9b8ee26d866d10bd93affa6785171514579050f238f9e6d2`).
These tests cover one junction escape and ordinary items on three fixtures;
they do not validate a newly online-only file before first open or other
providers. Rejecting all reparse points is deliberately
conservative; it does not yet support providers that expose online-only
cloud files as reparse points.

### Output alias failure in 0.1.14.0

A second disposable VM fixture selected `source` and a sibling folder
`output-link`. Windows confirmed `output-link` was a junction targeting
`source\inside-output`. The 0.1.14.0 worker accepted both selections because
their displayed paths are separate. It then wrote `phase1-probe.csv` and
`phase2-go-manifest-5084-15290578.csv` through the output link. An independent
guest inventory confirmed both files physically appeared in
`source\inside-output`; the pre-existing `document.txt` remained unchanged.
The Go manifest also included its own in-progress CSV as
`inside-output/phase2-go-manifest-5084-15290578.csv`, recorded at three bytes.
The initial WinRT walk had counted one file while the later Go manifest counted
two. **This is a confirmed source-write and self-inclusion failure in the
probe.** The 0.1.14.0 source-junction guard does not solve destination aliasing.

A signed 0.1.15.0 disposable build (SHA-256
`5881d2ac5740efa18552bc365f3ed28d14dcab2444eab2bb945ba534e32679d5`)
ran as an AppContainer worker in the VM. Before any output creation, it compares
the picker-selected output `StorageFolder` to the selected source and each
ordinary descendant using WinRT `IsEqual`; it rejects a match or an ambiguous
reparse entry. **This candidate failed:** `IsEqual` reported no match for the
selected output junction and its actual target inside the source. The worker
again wrote its manifest into `source\inside-output`; an independent read of
that file showed four rows, including its own in-progress three-byte CSV and
the two files written by the prior run. `StorageFolder::IsEqual` cannot be used
as the sole alias defense. The source-write gate is still failed.
After this result, the source tree gained a conservative check that refuses a
picker-selected output folder whose `System.FileAttributes` carries the
reparse-point bit. The signed 0.1.16.0 disposable build (SHA-256
`6b0ccdcb6e2be15fe87f44ccc3575c46b1981f8f2c4caefe350884ae36deccb6`)
runtime-tested that check. On the same output-alias fixture, the worker reported
`ERROR REFUSED output reparse point` before enumeration, manifest creation, or
output creation. A read-only inventory found no new 0.1.16.0 manifest in the
source tree.

The installed 0.1.16.0 probe then completed the known-good local and same-VM
SMB five-file fixtures and the 501-file Google Drive fixture. The collected
local and SMB manifests were byte-identical to the verified five-row oracle
(SHA-256 `44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`).
The Drive manifest was byte-identical to the verified 501-row oracle (SHA-256
`79adafa7e9374c4a9b8ee26d866d10bd93affa6785171514579050f238f9e6d2`).

This closes the **tested output-junction shape**. It is not a general resolved
identity or race proof. Hard links, other reparse types, DFS/provider aliases,
destination replacement after validation, and providers that conceal aliasing
remain open. At that probe stage, the Phase 2 source-write gate remained open.

## Production integration result

The probe findings above remain historical evidence. The product implementation
that followed them uses the shared engine behind a bounded native broker rather
than the probe's manifest path. Development-signed MSIX `0.2.5.0` had SHA-256
`2f6ec6409228e8337eb20d5d0cf2f5503be52ec90c1b7e110d3a9c156801790e` and
declared AppContainer trust with no network capability.

Runtime results in the Windows 11 VM:

- Local fresh run: five rows, including the Unicode path, byte-identical to the
  frozen oracle (`44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`).
- Same-VM SMB fresh run: five rows, byte-identical to the same oracle; source
  path, size, hash, timestamp, and attribute inventories were unchanged.
- Google Drive for desktop fresh run: 501 unique rows and 1,988,627 bytes,
  byte-identical to the verified Drive oracle
  (`79adafa7e9374c4a9b8ee26d866d10bd93affa6785171514579050f238f9e6d2`).
  The 1 MiB hydration control row retained its pre-upload SHA-256
  `233e72efb84d5a046de94bdab4e661b8d375335075f64f5e47048604b08a3f3c`.
- Cancellation/restart/resume: a 1,024-file, 268,435,456-byte fixture produced
  a valid version-3 checkpoint, restored both picker grants after a full host
  restart, and resumed to 1,024 unique rows. Comparison with the retained
  baseline found zero path, size, or hash mismatches; the checkpoint was removed
  after successful publication.
- Source containment: the production run refused
  `junction-fixture\source` with `source contains a reparse point or provider
  alias`; the output folder remained empty.
- Destination containment: the production run refused the output junction in
  `output-alias-fixture` with `selected destination is inside the selected
  source`; the junction target inside the source remained empty.

The focused suite
`go test . ./internal/... ./packaging/appcontainer-phase2/go-probe` passed after
the final provider-link policy change. It covers brokered fresh and resumed
runs, checkpoint identity, changed-file rehash, missing-file removal,
unreadable/error paths, hard-link rejection, and bounded protocol failures.

### Source-write trace

One bounded Windows Performance Recorder `FileIO` capture covered the final
local, SMB, and Google Drive product runs. Product host PID 4324 launched
contained worker PIDs 7860, 5584, and 12988. The repeatable analyzer at
`packaging/windows-appcontainer/analyze-source-write-trace.ps1` decoded the
199,229,440-byte ETL with Microsoft TraceEvent. The ETL SHA-256 was
`11e012f202532dc0eaf12f37bc6cde3df403f8c6e5a76db667ac2bd0fc6d934f`.

The trace found expected source opens/reads and **zero** source Write, SetInfo,
Delete, Rename, or creating-open events for the product host/worker PIDs in all
three storage classes. Writes appeared only under the selected destination
folders. The compact machine-readable result is
[`product-0.2.5-source-write-trace.json`](product-0.2.5-source-write-trace.json).

Phase 2 gate result: **PASS for this tested matrix.** This does not certify a
release or every provider. Separate-host/DFS behavior, additional cloud
providers, Windows 10, the final native wizard, final-artifact network/process
traces, production signing, and independent acceptance remain explicit later
gates.
