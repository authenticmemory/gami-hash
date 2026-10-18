# WebView2 inside AppContainer feasibility assessment

Date: 2026-10-17

Status: **All three bounded feasibility slices passed on the tested Windows 11
VM; signed-release acceptance remains open**

This assessment records the decision to test the existing WebView2 frontend
inside AppContainer before continuing the native Win32 parity rewrite. It does
not certify WebView2, Wails, or any release artifact beyond the tested
development package and scenarios described below.

## Source findings

The existing frontend is a good candidate for direct reuse:

- `gui.go` embeds `frontend/dist`; the page does not need a remote origin.
- `frontend/vite.config.ts` emits relative asset URLs.
- The deployed flow and styling live in `frontend/src`; a successful spike can
  retain them without recreating the screens.
- The frontend expects the Wails runtime and seven backend operations. Its
  defensive plain-browser mode is useful for visual previews, but it is not a
  substitute for proving the real bridge.

The existing Windows package is not the candidate:

- `packaging/msix/AppxManifest.xml` declares `Windows.FullTrustApplication`
  and `runFullTrust`.
- The Windows build uses Wails 2.15.0 and `go-webview2` 1.0.22. Wails creates
  an Evergreen WebView2 environment and leaves the user-data path at its
  default because `WebviewUserDataPath` is empty.
- `packaging/windows-appcontainer/IntegrationHost.AppxManifest.xml` has the
  required starting boundary: `Windows.PartialTrustApplication`,
  `uap10:TrustLevel="appContainer"`, `packagedClassicApp`, and no declared
  capabilities. That manifest currently launches the native Phase 4 host.
- The brokered storage implementation is already proven for the tested Phase
  2 and Phase 3 matrix. The spike should call that boundary after WebView2
  feasibility is established, not revive direct path access from the old
  Wails backend.

Public evidence does not settle compatibility. Microsoft documents WebView2
as a multiprocess runtime and describes AppContainer-hosted/UWP use, but an
open WebView2 report reproduces a blank control with the same
`packagedClassicApp` plus `appContainer` manifest shape. Source inspection can
therefore justify a test, not a compatibility claim.

## Proposed spike

Create `packaging/appcontainer-webview2-spike` as a disposable, separately
named package. Do not edit the Phase 4 host or its package identity.

### Slice 1: launch, render, and containment

1. Build the current `frontend/dist` and Wails Windows executable without
   changing the HTML, CSS, images, fonts, screen flow, or behavior.
2. Package that executable with a new AppContainer identity derived from the
   proven manifest shape. Declare no `runFullTrust`, `internetClient`,
   `internetClientServer`, or `privateNetworkClientServer` capability.
3. Set the WebView2 user-data folder to a package-local writable location.
   Record the exact WebView2 initialization HRESULT and runtime version when
   initialization or navigation fails.
4. Load only the embedded Wails asset server. Do not navigate to an HTTP(S)
   page and do not use `--no-sandbox` or another sandbox-disabling switch.
5. Capture a screenshot and exercise the real Wails bridge far enough to prove
   that JavaScript-to-host messaging works.
6. Enumerate the host and every descendant while the welcome screen is idle
   and while the bridge is exercised. Record image path, PID, parent PID,
   command line, package identity, AppContainer SID, `TokenIsAppContainer`,
   integrity level, and process role where available.

**Slice 1 gate:** continue only if the unchanged frontend renders, the real
bridge responds, and every app-owned WebView2 process is attributable and
inside the intended AppContainer boundary. Stop on a blank/failing control,
an uncontained required child, a required full-trust helper, or a workaround
that disables Chromium/WebView2 sandboxing.

### Slice 2: network negative controls

1. Observe launch, idle, bridge activity, and shutdown with process creation,
   DNS, TCP, UDP, loopback, private-network, WFP, and packet capture enabled.
2. Attempt TCP, UDP, DNS, loopback, and private-network traffic from a small
   diagnostic executable launched under the same package identity/token.
3. Run a positive control outside the boundary against the same listeners and
   capture window so silence can be distinguished from a broken test.
4. Attribute WebView2 browser, renderer, GPU, crash-handler, network-service,
   and other utility processes independently. API-level failure or success by
   itself is not packet-delivery evidence.

**Slice 2 gate:** continue only if the positive control is observed, none of
the contained negative controls is delivered, and no app-owned WebView2
process makes an unattributed or independently delivered connection. Any
delivered or unattributed connection fails the no-independent-network gate.

### Slice 3: brokered local fixture

1. Replace only the spike's seven-operation bridge with the narrow Phase 2/3
   broker contract; do not grant the old path-based Wails backend broader
   filesystem authority.
2. Select a small local source and separate output through the brokered picker
   path, approve any required classification, and create a manifest with the
   contained Go worker.
3. Compare the CSV byte-for-byte with its oracle and confirm that no
   full-trust helper appears.
4. Repeat the process/token and network captures during selection, preflight,
   hashing, output publication, and shutdown.

**Slice 3 gate:** the spike passes only if the expected manifest is produced,
every GAMI/WebView2 process remains in the intended boundary, and the network
gate remains clean. This local fixture answers feasibility only; SMB, cloud,
resume, cancellation, provider completeness, signing, and release acceptance
remain later gates.

## Overall pass and stop decision

The feasibility spike passes only when all three slices pass. A launch or
screenshot alone is not a pass. A capability-free manifest alone is not a
pass. Chromium's internal renderer sandbox alone is not the required package
boundary.

Stop the WebView2/AppContainer route at the first failed slice. Preserve the
artifact, manifest, HRESULTs, process-token inventory, and trace evidence, and
record the exact boundary that failed. Then make the explicit product choice
required by the handoff: a narrower evidence-based statement for the deployed
WebView2 UX, institution-managed firewall policy, or a separately scheduled
hardened native edition.

## Evidence labels

- The findings above are **source inspection**.
- A development-signed spike run would be **prototype evidence**.
- Only testing the exact signed release artifact on the acceptance matrix can
  become **signed-artifact runtime proof**.

## First Slice 1 VM observation

On 2026-10-17, the development-signed `0.1.0.0` spike launched for the
standard `gami_runner` user and rendered the original embedded frontend. The
user invoked both **Choose folder** and **Choose where to save**, proving that
the real Wails JavaScript bridge reached the host-side dialog operations.

The legacy Wails folder dialog reported `Access is denied` for
`C:\Users\gami_runner\Desktop`. The save dialog opened, but **Save** did not
complete the selection. This is prototype evidence that the old path-based
Wails picker/backend is not usable as the AppContainer storage implementation.
It is not evidence that the already proven brokered WinRT storage boundary is
infeasible, and Slice 3 was already designed to replace this backend.

The observation passes the Slice 1 render and bridge-invocation questions. A
subsequent corrected 30-second inventory found the host plus browser,
crashpad, GPU, network-service, storage-service, and renderer processes;
`TokenIsAppContainer` was true for all seven. Sysmon recorded the same launch
chain and one later GPU-process start rooted beneath the browser. The later GPU
process had exited before its token could be queried. Slice 1 is provisionally
passed for continuing to Slice 2, where a controlled restart must capture that
short-lived replacement and test network behavior. See the
[Slice 1 evidence](evidence/2026-10-17-windows-appcontainer-webview2/README.md).
No network conclusion follows from the Slice 1 observation.

Slice 2 subsequently passed for the tested development artifact and capture
window. The contained controls produced no delivered TCP, UDP, DNS, loopback,
private, or public traffic; outside-boundary IPv4/IPv6 TCP/UDP controls reached
the listeners. The WebView2 process tree made four loopback port 80 attempts,
all dropped, and made no observed private/public connection. See the
[Slice 2 evidence](evidence/2026-10-17-windows-appcontainer-webview2/SLICE-2-NETWORK.md).

## Slice 3 functional result

On 2026-10-18, development-signed spike `0.1.5.0` passed the local-fixture
functional gate. The unchanged WebView2 frontend selected a two-file source
and a separate destination through WinRT folder pickers. The spike-only C ABI
adapter retained the resulting `StorageFolder` objects, classified them with
the Phase 2/3 boundary, and launched the existing contained Go worker. The UI
reported two files and 35 bytes recorded.

The generated CSV contained exactly the two expected relative paths, byte
counts, and SHA-256 hashes. The tested MSIX SHA-256 was
`a516e72581987cdd8779e256431fb73d0365393138f2caeb9b5bd34c0352b475`.
See the [Slice 3 evidence](evidence/2026-10-17-windows-appcontainer-webview2/SLICE-3-STORAGE.md).

The assurance run then hashed eight 256 MiB local files while process-token
and packet captures were active. The collector observed the host, six WebView2
processes, the contained worker, and its console host; all nine had
`TokenIsAppContainer=true`. The outside-boundary TCP/UDP IPv4/IPv6 controls
reached their listeners, while no app-owned outbound packet to a monitored
loopback, private, or public target was observed. The eight-row manifest
recorded exactly 2 GiB.

**All three feasibility slices pass for the tested development artifact and
local-storage scope.** This answers the handoff question: the existing WebView2
frontend can run inside the capability-free AppContainer and use the existing
brokered storage worker without a full-trust helper. This remains prototype
evidence, not release acceptance. Development build `0.1.6.0` subsequently
passed cancellation, same-session resume, and **Open folder**. Development
build `0.1.15.0` then restored revalidated FutureAccessList grants across
process exit, displayed the persisted eight-row progress count, completed the
2 GiB run without folder reselection, terminated cleanly, and relaunched.
These results close the bounded restart-resume and lifecycle questions for the
prototype; release packaging and acceptance remain open.
