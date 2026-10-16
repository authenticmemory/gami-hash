# Decision 0001: Stop the direct-path Windows GUI migration

Date: 2026-10-16

Status: Accepted. Phase 2 implementation passed its tested engineering matrix;
release verification remains open.

## Context

The Windows GUI must run without app-owned internet access while still handling
user-selected local, SMB, and cloud-backed folders. The current v1.5.0 Go
engine uses ordinary filesystem paths. The proposed Windows package gives its
GUI and worker AppContainer tokens with no declared network capability, and
uses the Windows folder picker to grant storage objects.

The Phase 1 probe enumerated and hashed a five-file local fixture, a same-VM
SMB share, a separate-host SMB share, and a 500-file Google Drive for desktop
folder through WinRT storage objects. A diagnostic 1,024-file local run
cancelled and resumed after a GUI restart; an independent verifier found no
missing, duplicate, size, or hash mismatches. WFP and PktMon attributed tested
IPv4 blocks and loopback non-delivery to the contained worker. These results
do not constitute a release-wide no-network or no-write proof.

For the decisive path comparison, probe 0.1.2.0 bundled the **signed v1.5.0
Go CLI** (SHA-256
`119921fa70185f18b56c138c15d69c6a15e5bdeefd8adf32e483493b247a1569`).
The GUI, worker, and Go child ran in one AppContainer process tree. On the same
picked local fixture, the WinRT worker produced all five expected hashes, but
ordinary C++ path traversal failed before its first file. The Go child had
`TokenIsAppContainer=1`, exited 1, produced no CSV, and reported:

> error: invalid root folder: Access is denied.

Sysmon linked Go PID 6720 to contained worker PID 8172 and GUI PID 6580. The
package declared no network capabilities. Full details, hashes, and limits
are in the [Phase 1 VM record](../evidence/2026-10-16-windows-appcontainer-phase1/README.md).

## Decision

**Do not start a direct-path GUI rewrite.** Passing a picker-returned path to
the current Go engine does not preserve folder access inside this AppContainer.
Phase 1 therefore fails the direct-engine gate and stops at its planned
architecture decision. The next implementation slice is a narrow contained
storage adapter that accepts picker-granted storage objects or brokered handles
for enumeration, metadata, streaming reads, output creation, and persisted
access. Keep hashing incremental; do not copy whole collections into a staging
folder. Preserve the existing CSV and resume semantics through comparisons
against the current CLI.

The adapter must handle local, SMB, and cloud-backed providers without giving
the app direct network capability. Native Windows pickers and storage brokers,
the SMB client, and cloud sync providers may use the network on the user's
behalf; their traffic must be attributed separately from app-owned processes.
The GUI must identify recognized remote locations and request the user's
permission before hashing, with the picker-time caveat recorded in the
implementation plan. Source-read and output containment rules still require
separate enforcement and runtime checks.

## Phase 2 API finding (2026-10-16)

Probe 0.1.3.0 tested Windows' AppContainer-aware `*FromApp` file APIs on the
same picker-selected local fixture. `GetFileAttributesExFromAppW` and
`FindFirstFileExFromAppW` accessed the root, `CreateFileFromAppW` read one
file and created an output test file, and `DeleteFileFromAppW` removed that
test file. Ordinary C++ traversal still failed with access denied. These
results were reported from the VM's interactive probe run; the Go adapter
and SMB/cloud `*FromApp` paths had not yet passed runtime tests. A contained
Go child in probe 0.1.4.0 subsequently enumerated the same local root from
a `CreateFileFromAppW` directory handle, read a file with the expected SHA-256,
and created/deleted an output test file. On a same-VM SMB share, `*FromApp`
returned `ERROR_NETWORK_ACCESS_DENIED` for source and output while the WinRT
worker still succeeded. On the tested Google Drive for desktop mount, the
`*FromApp` calls did succeed, but only a one-byte read was attempted. The
candidate adapter may therefore need brokered WinRT file handles or streams
for SMB even if direct AppContainer-aware handles cover local and some cloud
paths. Probe 0.1.6.0 then passed one SMB source read handle and one separate
SMB output write handle from WinRT to contained Go; its source hash matched
the fixture. Recursive enumeration, safe publication and resume still need
the actual storage adapter. The direct ordinary-path decision above stands. See the
[Phase 2 evidence](../evidence/2026-10-16-windows-appcontainer-phase2/README.md).

## Rejected shortcuts

- Add broad internet or private-network capability to the package: this
  defeats the app-owned no-network boundary.
- Launch the Go engine as a full-trust helper: the GUI would no longer have a
  categorical process-tree boundary.
- Treat WinRT success as proof that an ordinary path will work: the signed Go
  CLI test directly disproved that assumption.
- Stage entire source trees in a local temporary directory: this duplicates
  sensitive material, consumes space, and changes file identity and resume
  behavior.

## Remaining verification before a product claim

The Phase 1 probe answers feasibility and the direct-path question; it is not
the product. Phase 2 must establish stable storage identity, source-write
prevention, output exclusion, changed/missing-file resume behavior, provider
error handling, and CSV parity. Re-test on a standard-user account, denied and
remapped SMB paths, cloud placeholders and cached files, other providers that
institutions actually require, and Windows 10 if it will be supported. A
release candidate still needs full process-tree, packet, WFP, and source-write
traces, including routable IPv6 and provider attribution, plus clean-install
and missing-WebView2 checks where relevant to the shipped artifact.
