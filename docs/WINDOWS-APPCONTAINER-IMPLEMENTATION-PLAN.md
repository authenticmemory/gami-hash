# Windows AppContainer GUI implementation plan

Status: **approved direction; planning only**. No product implementation has
started under this plan, and no released Windows GUI meets its assurance gates.
The signed v1.5.0 GUI still uses WebView2 and [failed the no-independent-network
claim](evidence/2026-10-16-windows-v1.5.0/README.md). This plan is for its
successor, not a retroactive certification of v1.5.0.

## Platform scope

This document implements the **Windows** assurance path. It does not certify
macOS or Linux. The common hashing-engine and service changes in Phases 2–3
should stay portable, but the sandbox, file picker, packaging, and runtime
network evidence must be designed and released separately for each OS.

| Platform | Current GUI and release state | Separate assurance path |
| --- | --- | --- |
| Windows | Wails/WebView2; signed v1.5.0 network test failed. | Native GUI in a real networkless AppContainer; this plan. |
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

Tasks:

1. Package and install it on a disposable Windows VM. Inspect the package
   manifest and live process tokens. Prove GUI and worker are AppContainer
   processes and no full-trust child is launched.
2. From those same tokens, deliberately attempt TCP, UDP, DNS, loopback, and
   private-network sockets. Each direct attempt must be denied. Capture the
   denial; merely seeing no traffic while idle is insufficient.
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

## Phase 2 — adapt storage and preserve the engine

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
