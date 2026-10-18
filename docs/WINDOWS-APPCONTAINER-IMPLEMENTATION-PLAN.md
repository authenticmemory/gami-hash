# Windows AppContainer GUI implementation plan

Status: **Phase 3 engineering gate and the bounded WebView2-inside-
AppContainer feasibility gate passed on the tested Windows 11 VM; release
acceptance remains open**.
The [architecture decision](decisions/0001-windows-appcontainer-storage-adapter.md)
directed Phase 2 toward a contained storage adapter. The production integration
host, contained worker, and brokered engine adapter pass the tested Phase 2
matrix, and the Phase 3 build adds identity-bound storage classification and
consent enforcement. The native product wizard and release acceptance work
remain, and no released Windows GUI yet meets the assurance gates.
The signed v1.5.0 GUI still uses WebView2 and [failed the no-independent-network
claim](evidence/2026-10-16-windows-v1.5.0/README.md). This plan is for its
successor, not a retroactive certification of v1.5.0. A development-only
WebView2 AppContainer spike has since rendered the unchanged frontend, passed
contained network controls, and produced an oracle-matching manifest through
the brokered worker with every observed process contained. The prototype also
passed cancel/resume in one session, persisted and revalidated picker grants
for resume after process exit, completed a restored 2 GiB run, and passed a
close/relaunch lifecycle check. See the
[feasibility decision](WINDOWS-APPCONTAINER-WEBVIEW2-FEASIBILITY.md). The
native wizard remains a fallback while the proven WebView2 route is
productized.

## Platform scope

This document implements the **Windows** assurance path. It does not certify
macOS or Linux. The common hashing-engine and service changes in Phases 2–3
should stay portable, but the sandbox, file picker, packaging, and runtime
network evidence must be designed and released separately for each OS.

| Platform | Current GUI and release state | Separate assurance path |
| --- | --- | --- |
| Windows | Wails/WebView2; signed v1.5.0 network test failed. | Productize the proven Wails/WebView2 AppContainer plus broker boundary, retaining the native wizard as fallback; then test the exact signed artifact. |
| macOS | Wails uses system WebKit. The current preview ZIP is ad hoc signed; production notarization and runtime network assurance are open. | Prototype a signed macOS App Sandbox build without outgoing-network entitlement. Test user-selected source/output access, network/cloud storage, WebKit child processes, cancel/resume, and source-write rights. Keep the web UI only if the full process tree meets the claim; otherwise use a native UI. Then notarize and test the exact artifact. |
| Linux | Wails uses WebKitGTK. The current `.deb`/`.rpm` packages declare GTK/WebKit dependencies and do not establish an app network sandbox; CI only smoke-tests launch. | Prototype a sandboxed distribution such as Flatpak with no `--share=network`, using file chooser/document portals for selected folders. Prove whole-tree reads, output, resume, and network-storage behavior. Treat ordinary `.deb`/`.rpm` builds as a separate, weaker assurance tier unless an enforceable sandbox is shipped and verified. |

Apple documents separate App Sandbox entitlements for outgoing network access
and user-selected file access. Flatpak documents a separate network permission
and brokered file-chooser portals. Neither fact proves that the existing Wails
GUI or hashing workflow works inside those sandboxes. Each platform needs its
own feasibility prototype and signed-artifact runtime capture before an
institutional statement covers it.

Release policy: publish a platform-specific assurance status. Do not say
"GAMI Hash GUI makes no internet requests" across all platforms until all
three packaged GUIs pass their own gates. The Windows work can proceed while
macOS/Linux remain explicitly unverified.

## Outcome and boundaries

Build a signed Windows GUI that retains the current hashing workflow and can
hash a user-selected local folder, SMB/UNC or mapped share, and supported
cloud-synced folder **without requiring a manual local copy first**. The GUI
and its app-owned worker processes must run in a real AppContainer with no
general network capability. Windows, its file-system client, or a cloud sync
provider may transfer bytes to service a selected file read or output write;
those transfers must be disclosed separately. GAMI Hash must not independently
connect to an internet service, upload source bytes, or perform telemetry.

"Any source" means a folder exposed through a supported Windows picker and
filesystem provider that the user is authorized to read. A remote website,
SharePoint URL without a local sync/provider integration, proprietary archive
API, or storage system invisible to Windows needs its own integration and is
outside this first release. Support is earned per provider by acceptance tests.

The source-file claim has two levels. The initial functional gate is that the
engine requests only read access and writes output/checkpoint/error artifacts
outside the source. A stronger "the process cannot modify source entries"
claim requires an OS-enforced read-only boundary and a failed write negative
control. Cloud hydration and filesystem access-time effects are outside a
promise that the physical storage remains byte-for-byte unchanged.

The release statement must name the **exact signed artifact, supported Windows
versions and storage providers, process tree, and test evidence**. It cannot
promise that the entire Windows machine emits no network packets.

## Current code and migration constraints

| Current component | Implication for the new build |
| --- | --- |
| `gui.go` and `frontend/src/main.ts` | Wails/WebView2 draws the current wizard. Replace the **Windows** GUI only; keep macOS/Linux behavior unless separately authorized. |
| `internal/wailsadapter/backend.go` | Its seven methods define the GUI behavior to preserve: select source/output, inspect resume, preflight, start, cancel, open output folder. The replacement must expose no broader authority. |
| `internal/app/service.go` | `Preflight` and `Start` call `engine.Validate`, which opens filesystem paths. `InspectResume` reads output. Consent must be enforced **before** these calls for a detected remote or uncertain location, not just by hiding a UI button. |
| `internal/engine` | The Go engine expects path-based `os.Open`/`ReadDir`, writes a CSV plus checkpoint/error log beside the chosen output, and rejects output inside the source. Picker-granted access may require a storage adapter rather than a path string. Preserve CSV and resume compatibility. |
| `internal/engine/entry_windows.go` | All **visible** reparse points are skipped to avoid link escape. Real cloud placeholders must be tested; if they appear as reparse points to this process, distinguish safe cloud-file tags from name-surrogate links without following arbitrary links. |
| `packaging/msix/AppxManifest.xml` and `build-msix.ps1` | Existing prototype is full trust (`Windows.FullTrustApplication`, `runFullTrust`) and packages Wails. It is not the AppContainer implementation. Build a separate prototype package and retire/replace this path only after acceptance. |
| `build-windows-installer.ps1` and NSIS | Current installer can launch an online WebView2 bootstrapper. The replacement must install and launch without WebView2 or an online prerequisite. |

## Target shape

```text
Native Windows GUI (AppContainer, no network capabilities)
  -> narrow application service / consent gate
  -> Go hashing engine or contained Go worker
  -> picker-granted source and destination storage
Windows SMB client / cloud sync provider may service those file operations
```

Use an MSIX package whose GUI explicitly has
`uap10:TrustLevel="appContainer"` and no `runFullTrust`, `internetClient`,
`internetClientServer`, `privateNetworkClientServer`, or equivalent network
grant. Microsoft documents that a normal WinUI/MSIX desktop app is usually
full trust unless explicitly configured otherwise, and that an AppContainer's
children remain in the container. The packaged GUI must not launch an
uncontained helper to make storage access work. Keep the existing CLI as a
separately distributed tool unless its package identity and token are proven;
do not put a full-trust CLI in the assured GUI package.

The native UI technology is selected **after Phase 1**. Prefer a supported
Windows native framework that can run in AppContainer and use brokered pickers.
The engineering choice must preserve the Go engine or provide a validated
in-process/contained-worker bridge. Do not choose a framework solely because
its screens are quick to port.

## Phase 0 — freeze the contract and baseline

Tasks:

1. Record the current v1.5.0 GUI feature checklist and CSV/resume fixtures:
   local hashing, progress, warnings, cancel, close/reopen/resume, moved-root
   confirmation, output-outside-source validation, and error reporting.
2. Record the exact version and hash of the signed baseline installer and keep
   the existing evidence read-only. Mark its WebView2-missing test **not
   tested**, rather than converting source inspection into a runtime result.
3. Define a test matrix for Windows 10/11, standard-user accounts, NTFS,
   removable media, UNC/mapped/DFS SMB, OneDrive/SharePoint synced folders,
   online-only placeholders, cached cloud files, and at least one other cloud
   provider actually requested by an institution. Include local and remote
   **destinations** as well as sources.

Deliverable: baseline fixture set, provider matrix, and a versioned list of
supported scenarios. Gate: every claim has a measurable acceptance test.

Phase 0 artifact: [frozen baseline, fixtures, matrix and support list](WINDOWS-APPCONTAINER-PHASE-0-BASELINE.md).

## Phase 1 — prove AppContainer and picker feasibility

Build a minimal, separately named **prototype**, not a release GUI. It needs
only two pickers, a status window, a contained worker, and diagnostic output.

Prototype and current test status: [Phase 1 probe](../packaging/appcontainer-phase1/README.md).
First [VM run record](evidence/2026-10-16-windows-appcontainer-phase1/README.md):
picker-granted WinRT streaming worked for local, same-VM SMB, separate-host
SMB, and Google Drive for desktop folders; ordinary path traversal failed.
Two tested off-loopback UDP sends were dropped after an API-level success;
a later WFP/PktMon run independently attributed IPv4 drops and loopback
non-delivery to the contained worker. The diagnostic 1,024-file fixture
cancelled after 64 files and resumed to a fully verified CSV after GUI restart.
The separate-host share was removed after testing and a saved-token retry
failed with a missing-file error. The signed v1.5.0 Go CLI was subsequently
launched as a contained child by prototype 0.1.2.0 and
failed to read the picked local root with `Access is denied`; the same root
worked through WinRT. The Phase 1 direct-engine gate therefore failed.
Further process/network attribution and provider, failure, and standard-user
matrix checks remain open for the storage-adapter and release gates. They do
not justify a direct-path GUI rewrite.

Tasks:

1. Package and install it on a disposable Windows VM. Inspect the package
   manifest and live process tokens. Prove GUI and worker are AppContainer
   processes and no full-trust child is launched.
2. From those same tokens, deliberately attempt TCP, UDP, DNS, loopback, and
   private-network sockets. Prove that direct traffic cannot leave the app's
   network boundary, using API results plus packet/WFP drops and a positive
   control. UDP `sendto` may return success before Windows drops the packet;
   API success or silence alone is insufficient.
3. Pick a local folder and output, then an authenticated SMB share through UNC
   and a mapped drive, then an online-only cloud folder. Without adding network
   capabilities, enumerate **all children**, stream large files into SHA-256,
   and write output. Test both WinRT storage-object access and passing a picked
   path to the current Go worker. Do not assume the two grant equivalent rights.
4. Close/restart the prototype and reopen the selected location through an
   approved persisted picker token. Verify cancel/resume, remapped drive, and
   expired/revoked access behavior. A successful single-file pick does not
   satisfy the whole-folder or resume requirement.
5. Capture process/network activity. A system SMB client or sync provider may
   transfer file data; no GAMI process may gain direct socket access. Test
   authenticated, disconnected, and denied sources and output folders.

Deliverable: prototype code, development-signed test package, test log with package hash,
manifest, process-token evidence, picker results, and packet/process traces.
Gate: all three source classes and output classes work; every app-owned process
has no direct network capability. If this fails, **stop the GUI rewrite** and
write an architecture decision record. Possible alternatives are a brokered
storage-stream adapter or a revised assurance boundary; a silent full-trust
helper or broad network capability is not an acceptable workaround.

Outcome: **STOP the direct-path rewrite**. Picked WinRT storage objects worked
in the tested configurations, but the bundled signed v1.5.0 Go CLI could not
read the same picked local root from its AppContainer token. The
[decision record](decisions/0001-windows-appcontainer-storage-adapter.md)
selects a contained storage adapter for Phase 2. The untested standard-user,
provider, and network routes remain explicit gates on that adapter and the
release; the Phase 1 probe does not certify them.

## Phase 2 — adapt storage and preserve the engine

Production implementation outcome (2026-10-16): the repository now contains a
versioned, length-bounded Go/native protocol, a contained Go worker that calls
the product engine, brokered source and destination engine adapters, and native
Windows identity, broker-session, and worker-launcher components under
`packaging/windows-appcontainer`. The native components compile into
`GamiHashStorageBroker.lib`; the focused Go suite passes. Brokered cancellation,
checkpointing, restart/resume, stable source identity, hard-link rejection, and
race-aware destination publication are integrated. Providers that cannot
expose the required identity or link capability fail closed.

Current investigation: the [Phase 2 local handle probe](evidence/2026-10-16-windows-appcontainer-phase2/README.md)
shows that a contained Go child can enumerate a picker-selected local folder,
stream a file and create/remove a temporary file in the separate selected
output through Windows' AppContainer-aware `*FromApp` APIs. The same APIs
returned network-access-denied on a picker-selected same-VM SMB share where
WinRT streaming succeeded. A later probe passed one SMB source read handle
and one separate SMB output write handle from WinRT to a contained Go child;
the child's hash matched the fixture. A follow-up probe duplicated both
handles into an already-running contained Go child on local, same-VM SMB,
and Google Drive fixtures and matched the tested files' hashes. A local
`*FromApp` backend alone cannot
cover SMB, but brokered handles are feasible for this test share. The full
engine and Phase 2 gate remain open.

A disposable follow-up streamed complete five-column Go manifests through
picker-granted handles: five-file local and same-VM SMB CSVs matched the
compact fixture, and a cached 500-file Google Drive CSV matched the earlier
source-verified inventory. A fresh, user-observed online-only Drive file was
then read successfully and produced an exact pre-upload SHA-256 in a 501-row
manifest. A later acknowledged per-file protocol using the engine's shared
hash/row functions reproduced the local, same-VM SMB, and 501-file Drive
CSVs. The acknowledged probe also wrote an oracle-matching five-row CSV to
a temporary share on a genuinely separate host, with the host source file
hashes unchanged. These probes have no product resume/error pipeline,
provider identity enforcement, or source-write attempt trace.
The next signed probe fixed one global CSV sorting defect, but a disposable
junction fixture proved that the current WinRT walker follows a folder link
outside the selected source and hashes the outside file. Phase 2 source
containment therefore **fails** until a raw reparse/identity guard is
implemented and retested. See the Phase 2 evidence before using this broker
on any untrusted collection.
The first raw-directory-handle diagnostic was denied by AppContainer, so it
did not expose the junction tag. A shell-attribute query reported the reparse
bit on the fixture's junction, and a subsequent signed probe refused that
junction before hashing beyond it. The guarded probe preserved the verified
five-row local and same-VM SMB manifests and the 501-row Google Drive
manifest. This passes one local escape fixture and three known-good
regressions; provider identity and first-open cloud behavior remain open.
An output-alias fixture exposed a separate failure: an output junction whose
target is inside the selected source passed the probe's lexical path check.
The probe wrote both CSVs into the source and included its in-progress CSV in
the manifest. A signed folder-identity experiment using WinRT `IsEqual` also
failed: Windows reported no equality between the output junction and its
source-tree target, and another CSV landed inside the source. A signed
0.1.16.0 follow-up conservatively refused any selected output folder reported
as a reparse point. It rejected the known output junction before enumeration
or output creation, then preserved the byte-identical local, same-VM SMB, and
Google Drive manifests. This closes that tested junction shape only. Hard
links, other reparse types, provider and DFS aliases, publication races, and
stable resume identity remain open. No probe result should be treated as Phase
2 completion; the product still needs a verified identity and publication
design.

The production adapter subsequently replaced those probe-only checks with
opened-handle identity validation and fail-closed publication. Development-
signed production integration package `0.2.5.0` completed local, same-VM SMB,
and Google Drive fresh runs. Local and SMB output matched the frozen five-row
oracle byte for byte; Google Drive produced the verified 501-row,
1,988,627-byte oracle, including the exact pre-upload hash of the previously
online-only control file. A 1,024-file, 256 MiB run cancelled, survived a full
host restart, and resumed without missing, duplicate, size, or hash mismatches.
The product refused both a source junction escape and an output junction that
resolved inside the source before creating output.

A bounded WPR FileIO trace covering all three successful storage classes found
source reads but zero product-tree source Write, SetInfo, Delete, Rename, or
creating-open events. Focused Go tests cover unreadable files/error logs,
changed and missing resume entries, hard links, cancellation, and protocol
failure paths. Gate result: **PASS for the tested Phase 2 matrix.** This is an
engineering gate, not release certification. Separate-host/DFS variants,
additional cloud providers, Windows 10, final-artifact network attribution, the
native wizard, signing, and independent acceptance remain later-phase gates.
See the [Phase 2 evidence](evidence/2026-10-16-windows-appcontainer-phase2/README.md).

Subsequent Phase 3 verification narrowed the cloud completeness result. The
Google Drive source contained 502 filesystem entries, including hidden
`desktop.ini`, while the production WinRT broker returned 501 entries and
omitted only that hidden file. An experimental raw-handle walker included all
502 entries but failed on the local AppContainer fixture with access denied, so
it was not retained. The Phase 2 pass therefore applies to the tested entries
exposed by Windows.Storage; a claim that every filesystem entry is included is
still open. This limitation does not bypass or invalidate the Phase 3 consent
gate, but it must be resolved before collection-completeness acceptance.

Tasks:

1. If picked paths work under AppContainer, retain the existing Go engine and
   keep its path canonicalization and output-exclusion checks. If paths fail,
   introduce a narrow storage interface for enumerate, metadata, read stream,
   output create/replace, and persisted access. Use brokered storage objects or
   handles; do not stage whole collections locally or load entire files into
   memory. Make storage identity stable enough for resume and moved-root checks.
2. Keep source reads read-only. Keep output CSV, `.part.json`, errors, and
   temporary files outside the resolved source. Audit hard links, reparse
   points, provider aliases, and network paths so an output path cannot resolve
   back inside the source. Fail closed when identity cannot be established.
3. Test real cloud placeholders. Windows Cloud Files providers can hydrate a
   placeholder when opened, and usually hide their reparse points from ordinary
   apps. If the new process sees a cloud reparse point, distinguish its tag and
   validate containment before treating it as a regular file. Preserve the
   skip rule for junctions, symlinks, and other escape-capable entries.
4. Compare new GUI output with the current engine/CLI on the same fixtures:
   CSV rows and hashes, Unicode/long paths, unreadable files, error log,
   cancellation, resume, and missing/changed files. The GUI must not silently
   omit a cloud file while reporting a complete collection.

Deliverable: storage adapter only if needed, engine changes, and regression
fixtures. Gate: same hashes/manifest semantics as the current engine and no
source-tree write requests in local, SMB, or cloud runs.

## Phase 3 — classify both paths and enforce consent

Engineering outcome (2026-10-16): development-signed package `0.3.5.0`
(SHA-256
`eeefe631654e540fedd68a41df7dc1840af0936713daef26e1aec8cef0a15995`)
classified both selected folders before worker launch and bound the decision to
their opened-handle identities. The launcher and broker independently
reclassified and validated that authorization before preflight or output
creation. Local storage proceeded without a notice. UNC SMB and Google Drive
were classified as `Network/cloud`, displayed their paths and reasons, and
required explicit approval. Declining SMB Fresh and Google Drive Resume left
the corresponding destination snapshots unchanged; a later attempt prompted
again. Approved local, SMB, and Google Drive Fresh runs exited 0. The existing
junction and output-alias refusal checks also remained effective.

Focused native tests cover local automatic authorization, network/cloud and
unknown denial and approval, source and destination substitution,
reclassification, remap, and resume invalidation. The UI states the timing
limit: picker browsing and classification metadata may already contact a
provider, while approval is guaranteed before GAMI starts preflight, hashing,
or output creation. This is a conservative classifier and is not proof that
every third-party storage provider will be detected. Gate result: **PASS for
the tested Phase 3 matrix.** See the [Phase 3 evidence](evidence/2026-10-16-windows-appcontainer-phase3/README.md).

Tasks:

1. After the user picks **source and destination**, classify each as `Local`,
   `Network/cloud`, or `Cannot determine` using path/volume identity, remote
   drive information, registered sync roots, placeholder/provider metadata,
   and resolved aliases where available. This is a conservative classifier,
   not a proof that arbitrary third-party storage is local. Record the reason
   for each classification without reading file contents.
2. For either detected network/cloud location, show one notice naming the
   location and what may happen: source bytes can be fetched/read over a
   network; the CSV/checkpoint/error log can be written or synced remotely.
   Require explicit approval **before preflight scans, hashing, or output
   creation**. If both are confirmed local, proceed without that notice.
3. For `Cannot determine`, say so and offer another selection or explicit
   approval of the uncertainty. Never silently classify unknown as local.
   Declining returns to selection and creates no output.
4. Move the gate into `internal/app` or the replacement service boundary:
   `InspectResume`, `Preflight`, and `Start` must require a valid classification
   and consent decision. Bind consent to the selected storage identities, not
   only to display strings. Reclassify on resume, remap, permission change,
   and path replacement; stop and ask again when material facts change.
5. Document the timing limit: browsing in the Windows picker and asking a
   provider for classification metadata may itself contact that provider
   before the post-selection notice. The notice guarantees approval before
   GAMI begins the hash/output operation, not before every possible OS packet.

Deliverable: source/destination classifier, consent UI and state contract,
tests for denial, unknown paths, substitution, remap, and resume. Gate: no
engine preflight read or output write can bypass the gate; local flow remains
one-click after selection. Do not claim perfect remote-source detection.

## Phase 4 — build the native Windows wizard

Follow-up status (2026-10-18): the WebView2-inside-AppContainer feasibility
gate passed, so the proven bridge and lifecycle were promoted into the
production-owned Windows AppContainer components instead of replacing the
deployed interface with the native wizard. Development candidate `1.6.7.0`
now uses the stable `AuthenticMemory.GAMIHash.Windows` package identity and
has passed local, UNC SMB, mapped-drive, cached Google Drive, changed-file
resume, revoked-grant recovery, upgrade-while-open, clean shutdown, and a
1,000,000-row interrupted-manifest restore. Enumeration startup was reduced
to about six seconds locally and eight seconds over SMB for the 1,024-file
fixture. Detailed engineering evidence is under
`docs/evidence/2026-10-18-windows-appcontainer-productization/`.

This does not close the release gate. A genuine online-only cloud placeholder
has not been exercised, `1.6.7.0` is signed with a disposable development
certificate, and process containment plus network capture must be repeated
against the exact organization-signed release artifact.

Signed-candidate follow-up (2026-10-18): organization-signed `1.6.10.0`
(SHA-256 `4b9b9e10e11b682b18e5814106edb86456995d399bf5706121c4525753911f84`)
passed process containment plus idle, local, UNC SMB, and cached Google Drive
captures. All observed GAMI/WebView2 processes were AppContainer-contained;
Sysmon attributed no network or DNS events to that process tree in the captured
windows; and every output manifest independently matched its fixture. See
`docs/evidence/2026-10-18-windows-appcontainer-signed-1.6.10/`. The exact-build
socket negative control and a genuine online-only placeholder remain open.

Implementation status (2026-10-16): native package candidate `0.4.4.0` is
built and development-signed. It replaces the diagnostic host with native
Win32 welcome, collection, result-file, review/consent, progress, canceled,
failure, and completed screens. Progress and terminal result data now cross
the bounded native/Go storage protocol; persisted state is limited to
FutureAccessList tokens and the CSV name. Static PE inspection shows no
WebView2, WinHTTP, WinINet, Winsock, URLMon, or browser dependency. Runtime
and non-developer usability acceptance remain open until the candidate is
installed and exercised in the standard-user VM.

Tasks:

1. Implement the current flow: welcome, choose collection, choose result file,
   review/consent, progress, and result. Preserve clear error, warning,
   canceled, and completed states, file/byte progress, and "Continue now".
2. Replace Wails' bridge and browser local storage with native equivalents.
   Keep only the narrow service operations. Persist only paths/tokens and run
   state needed for resume; never persist source contents or credentials.
3. Handle access revocation, unavailable shares, cloud provider failures,
   placeholders that cannot hydrate, and output failure with actionable errors.
   Verify keyboard navigation, scaling, and a standard-user install/launch.
4. Validate against the Phase 0 GUI checklist with an archivist or other
   non-developer user, including a network share and a cloud folder.

Deliverable: native GUI and usability report. Gate: feature parity and no
WebView2/browser child process at runtime.

## Phase 5 — package, sign, and migrate

Tasks:

1. Create a dedicated AppContainer MSIX build path; do not edit the current
   full-trust prototype in place until the new path is proven. Pin all build
   dependencies and make the installer/package usable without an online
   WebView2/bootstrap step. Inspect the unpacked signed package.
2. Remove Wails/WebView2 from the Windows GUI artifact and dependency
   inventory. Keep other platforms and the separately signed CLI functional.
3. Decide whether the existing NSIS installation can upgrade to MSIX directly.
   If not, document a safe, user-visible migration that preserves CSV,
   checkpoints, and source files. Test side-by-side beta, upgrade, uninstall,
   and rollback on copies in a snapshot-backed VM.
4. Verify package identity, token, capabilities, signature, checksum, and
   distribution path for each architecture. Ensure no updater or installer
   helper undermines the runtime claim.

Deliverable: signed release candidate, checksums, migration instructions, and
package audit. Gate: clean installation without WebView2; no undeclared
full-trust or network-capable process in the assured package.

## Phase 6 — independent acceptance and statement

Tasks:

1. On clean Windows VMs, monitor process creation, direct network flows, DNS,
   packets, and source-tree file operations during install, launch, idle,
   local hash, SMB hash, cloud-placeholder hash, cancel, resume, and exit.
   Attribute GAMI processes separately from Windows SMB/DFS and sync clients.
2. Run the direct-socket negative control in the same AppContainer token.
   Run a source-write negative control against selected storage. A denied
   write proves an OS boundary only for the tested access route; if it is not
   denied, use the narrower "does not request writes" claim and keep the
   stronger gate open.
3. Independently compare source content hashes and CSV output against fixtures;
   inspect Process Monitor requested access, including rename/delete/metadata
   changes. Note expected provider hydration, access-time, and sync effects.
4. Store raw sensitive traces privately and a redacted report under
   `docs/evidence/`. Update `docs/WINDOWS-ACCEPTANCE.md` with explicit
   PASS/FAIL/NOT TESTED for the **new build**; do not reuse v1.5.0 results.
5. Issue a short institutional statement naming version, artifact hash,
   supported storage types, what the app process cannot do, what selected
   storage providers may do, and the measured limits. Repeat for every release.

Gate: a failed, missing, or unattributed network/source-write observation
blocks the categorical claim. Installation success while disconnected is only
one test; it is not proof of no network attempts.

## Stop/go rules

| Finding | Action |
| --- | --- |
| Picked SMB or cloud folder cannot be fully read/resumed without app networking | Stop after Phase 1; design a brokered stream interface and re-audit its process/network authority. |
| Only a full-trust helper can access required storage | Do not call the package network-incapable. Seek an explicit architecture decision and a narrower claim. |
| Location type is uncertain | Ask consent or choose another location; never silently certify it local. |
| New engine skips online-only cloud files | Fail the provider gate; do not publish an apparently complete manifest. |
| Selected source is writable by the app despite read-only code paths | Keep the "cannot modify" claim open; do not describe observation as enforcement. |
| Any WebView2/browser or other app-owned process connects independently | Fail the no-independent-network gate. |

## Platform references

- [MSIX AppContainer configuration and child-process boundary](https://learn.microsoft.com/en-us/windows/msix/msix-container)
- [AppContainer network restriction](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [Desktop trust levels and picker access to network shares](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations)
- [Picker grants and future access](https://learn.microsoft.com/en-us/windows/apps/develop/files/file-access-permissions)
- [Cloud placeholders, hydration, and reparse compatibility](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine)
- [Apple App Sandbox network and selected-file entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Flatpak network permissions and portals](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
- [Linux file chooser portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html)
