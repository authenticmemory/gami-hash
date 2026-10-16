# GAMI Hash v1.5.0 Windows runtime observation

Tested 2026-10-15 22:46–23:02 UTC (2026-10-16 00:46–01:02 in Kigali) in a
disposable VMware Workstation Windows 11 Pro VM. The checkout was tag `v1.5.0`,
commit `8d5062ec62c18f2b4605522269b870412522ca57`. The installer came from
[Authentic Memory's tools page](https://authenticmemory.org/tools/), with the
adjacent published Windows checksum file. This report describes this run; it
is not a universal assertion about every Windows version, WebView2 version,
user profile, network, or future release.

A [follow-up TLS inspection](followup/README.md) of the same signed build
identified 13 requests from its WebView2 tree, including Microsoft account
profile requests with authorization headers. That later evidence supplements
the encrypted-traffic observations below.

## Decision

**The current Windows GUI cannot be described as making no internet
connections.** The `GAMI Hash.exe` process created a WebView2 process tree.
Sysmon attributed outbound TCP/443 connection events to that tree, and the NIC capture
corroborated packets in both directions for 12 of 13 distinct flows. This is
observable network use even if the hashing engine has no upload code. The
encrypted traffic was not decrypted, so these traces do not establish its
request contents or prove that source file contents were never transmitted.

**The selected source folder was read, with no source writes observed in this
run.** Process Monitor recorded 17,017 GAMI Hash operations under the stable
source path, including 3,590 `ReadFile` events and 2,580 `CreateFile` events.
The latter requested `Generic Read` (516), `Read Attributes, Synchronize`
(517), or `Read Attributes` (1,547). The filtered trace contains no write-like
operation or write-capable open. The 514-row manifest independently matched
all 514 source files' SHA-256 and size. This is bounded evidence for the tested
fixture, not a proof about every storage device or error path.

A later scan of the retained, unfiltered Process Monitor CSV checked **all
process names** for this exact source-folder path. It found 17,017 GAMI Hash
events, 3,550 `System` events, and 21 Explorer events. It found **no WebView2
event** under the source path and no write-like event or write-capable open
among the matching events. See
[source-all-process-summary.json](source-all-process-summary.json) and
[the streaming analysis script](analyze-source-all-processes.ps1). This still
describes one capture window, not an operating-system-enforced access boundary.

## Environment and procedure

- Windows 11 Pro build 26300; VMware Workstation VM. The WebView2 Evergreen
  Runtime `155.0.4283.60` was present before installation. The VM had been
  configured to boot without its VMware vTPM/encryption, so this was not an
  untouched default Windows 11 VM. A Microsoft account and other Microsoft
  applications were present; background OS traffic was expected.
- Installer SHA-256:
  `ae0fb30322f923c63d55c43ee3e531be4f7114ae0cb911ed6524bdb0fedea308`,
  matching `SHA256SUMS-windows.txt`. Authenticode status was `Valid`, signed by
  Authentic Memory gemeinnützige UG (haftungsbeschränkt) and timestamped by
  Microsoft. The installed `GAMI Hash.exe` and `gami-hash.exe` signatures were
  also `Valid`; the generated `uninstall.exe` was `NotSigned`.
- Sysmon captured process creation (ID 1), network connections (ID 3), and DNS
  queries (ID 22) using [sysmon-config.xml](sysmon-config.xml). A controlled
  `example.com` DNS lookup and TCP connection from PowerShell produced both
  expected event types before testing the app; see
  [sensor-control-result.json](sensor-control-result.json).
- `pktmon` captured NIC packets without an address filter, in a 128 MB circular
  ETL file. The final file was 5.7 MB and reported zero lost events. Process
  Monitor recorded file system operations during the stable GUI run. Monitor
  output was stored outside the selected source folder.
- An initial GUI run mistakenly selected the parent `GamiHashTest` folder and
  produced 546 rows while monitoring files in that folder were changing. Its
  CSV was excluded from the source-file conclusion. The
  corrected source was `C:\Users\Public\Documents\GamiHashTest\source` (514
  disposable files, about 2.0 GiB); output was in the sibling `output` folder.
- The corrected GUI run completed; [stable-verification.json](stable-verification.json)
  records 514 rows and zero independent hash, size, or record-ID mismatches.
  A separate GUI run was cancelled; the GUI displayed “Stopped. Nothing is
  lost.” and offered “Continue now.” After continuing, the final manifest
  matched the uninterrupted manifest byte for byte (SHA-256
  `4b18e5080b9b6bf9562febc2cdeaa292acf9858fd5f7e79fe4bf31a6762188cb`).

## Network findings

Sysmon event ID 1 identified `GAMI Hash.exe` PID 796 and its WebView2 browser
PID 9912, whose command line includes `--webview-exe-name="GAMI Hash.exe"` and
the app-specific `EBWebView` user data path. PID 9912 created 15 WebView2
children during the capture. The network-service child was PID 5916. There
were no ID 3 or ID 22 events attributed directly to `GAMI Hash.exe`; the
observed events were in its WebView2 tree.

| Time (UTC) | Attributed process | Observation |
| --- | --- | --- |
| 22:48:24–25, app startup | WebView2 network service PID 5916 | TCP/443 to `52.123.243.147`; two of three distinct source-port flows corroborated by NIC packets |
| 22:48:29 | PID 5916 | DNS query for `wpad` returned status 1460 |
| 22:49:23 and 22:50:48, GUI open | PID 5916 | TCP/443 to `150.171.27.11`; both flows corroborated by NIC packets |
| 22:50:39 | WebView2 browser PID 9912 | DNS query for `substrate.office.com`; TCP/443 to `40.104.15.66` |
| 22:50:39–23:00:28 | PID 9912 | Eight TCP/443 flows to `40.104.15.66`, all corroborated by NIC packets; some occurred during the stable or cancellation phases |

The WebView2 process tree also contacted the VM DNS gateway
`192.168.247.2:53`. The NIC packets demonstrate actual exchange for 12
flows, not merely a local connection attempt. One Sysmon connection event
to `52.123.243.147` had no matching NIC packet; it is not counted as a
corroborated exchange. [network-summary.json](network-summary.json) lists
the individual process GUIDs, source ports, destinations, and packet counts.
For each of the 12 packet-matched flows, a separate timestamp check found a
packet with the same four-tuple within 2 seconds of its Sysmon connection
event. These observations establish process attribution to this GAMI Hash
instance's WebView2 tree, but do not identify which application or runtime
component requested each connection.
No request URLs, HTTP bodies, or TLS plaintext were captured; the relationship
between a destination IP and a service name is not established by the IP alone.

The WebView2 command line already contained
`--disable-features=msSmartScreenProtection`. That flag did not eliminate the
observed connections. OS, Edge, Defender, Office, and other processes also
generated traffic in the unfiltered capture; the findings above use Sysmon
process GUID ancestry and the matching NIC 4-tuples to isolate this app's
WebView2 tree. The phase markers contain one operator labeling mistake:
`resume_start` at 22:56:03 UTC occurred before the stable run; the real
cancel/resume phase began at 22:59:32 and 23:01:12 respectively.

## WebView2 absent: open test

This VM already had WebView2, so its missing-runtime installer behavior was
**not tested**. The release's NSIS script calls `wails.webview2runtime`.
The pinned Wails macro checks the runtime registry key and, if absent, launches
the embedded `MicrosoftEdgeWebview2Setup.exe` Evergreen **online
bootstrapper**. This is a source-code expectation, not an observed result for
v1.5.0 on a runtime-free VM. The installer may therefore require internet
access to complete that branch. A separate VM image with no WebView2 runtime
must test whether the installer prompts, fails, or downloads, and record
network activity and user-facing behavior.

After the main capture, we took the VMware snapshot
`Before-WebView2-missing-test`, uninstalled GAMI Hash, and attempted to remove
the WebView2 runtime using its signed installer with
`--uninstall --msedgewebview --system-level --force-uninstall`.
[webview-removal.json](webview-removal.json) records exit code `93`; the
runtime's version remained registered, its executable remained present, and
WebView2 processes were still running. We therefore did **not** run the GAMI
installer or claim to have exercised its missing-runtime branch. We restored
the snapshot, booted the VM, and verified that the installed GAMI Hash and
WebView2 executables were present again. The snapshot is retained for review.

## Recommended correction before an institutional “no internet” claim

1. Withdraw the unqualified “No internet use” claim for the current Windows
   GUI. The wording below is supportable for this release.
2. Diagnose the WebView2 endpoints and prevent both application navigation
   and runtime background traffic. As an experiment, expose WebView2 browser
   arguments through the pinned Wails integration and test Chromium's
   `--disable-background-networking` switch. The current Wails Windows options
   do not expose a general browser-arguments field; the pinned
   `go-webview2` loader also replaces the external
   `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` environment value, so an
   environment variable alone is not a reliable product fix. Intercept and
   reject external WebView2 requests/navigation at the WebView boundary.
   Neither step is proof of no egress until the entire process tree is
   recaptured. Microsoft documents [WebView2 browser flags](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags)
   and [request interception](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/webresourcerequested).
3. For a hard offline guarantee, enforce outbound denial in the target
   environment and repeat the tests with a dedicated WebView2 runtime or
   isolation policy that does not block unrelated WebView2 apps. Treat the
   runtime updater and installer separately from the GUI process tree.
   Consider a native GUI if the WebView2 runtime cannot satisfy the guarantee.
4. Replace the online bootstrap path with a documented offline WebView2
   provisioning choice, then test the missing-runtime scenario. Re-run
   startup, idle, hashing, cancel, resume, and update tests on a fresh VM.

## Suggested statement for Dachau now

> We tested the signed GAMI Hash v1.5.0 Windows release in a disposable
> Windows 11 VM. During a 514-file test, GAMI Hash opened the selected source
> files for reading, made no observed write-capable access to that source
> folder, and produced a manifest matching every source file. The Windows
> graphical interface uses Microsoft WebView2, whose child processes made
> external network connections during the test. A follow-up capture attributed
> 12 Microsoft account profile/image GET requests with authorization headers
> and one browser component update POST to those child processes. We therefore
> cannot state that the current Windows application never uses the internet.
> The inspected request bodies contained no selected source-file contents;
> this bounded test does not prove that no file contents could ever leave.

Do not shorten that to “only reads files and does not use the internet.” The
first clause is supported within this test's scope; the second is false for
the tested release.

## Evidence and reproduction

- [phase-markers.csv](phase-markers.csv), [environment.json](environment.json),
  [release-checksum.txt](release-checksum.txt),
  [installer-signature.json](installer-signature.json),
  [file-verification.txt](file-verification.txt), and
  [installed-files.json](installed-files.json) record timing, VM, and artifact
  identity. Process creation and packet logging were independently validated
  with [sensor-control-events.json](sensor-control-events.json).
- [app-sysmon-events.json](app-sysmon-events.json) holds the relevant app
  process-tree events from Sysmon IDs 1/3/22; [network-summary.json](network-summary.json)
  gives source-port to NIC-packet correlation. The local raw Sysmon export
  (`sysmon-operational.evtx`), bounded unfiltered export (`sysmon-events.json`),
  raw NIC trace (`gami-network.etl`), and its `pktmon etl2txt` rendering
  (`gami-network-text.zip`) are retained in this directory on the test
  workstation. With those local files present, `python analyze-network.py`
  regenerates the correlation. The raw ETL SHA-256 is
  `2cd9377b1fcd218d41c7c9ee0dc095fad1bd112d798197ace8100805c3cf2901`.
- The local `gami-file-access.zip` contains the 661 MB raw Process Monitor
  PML (ZIP SHA-256
  `43a004f816364201cba71f1fc0710483309c113bd32bea8f3ad074f074f11ce8`).
  [procmon-source-events.csv](procmon-source-events.csv) and
  [procmon-source-summary.json](procmon-source-summary.json) are the filtered
  source-folder findings. The PML can be opened with Microsoft Process
  Monitor; the filtered CSV came from its `/OpenLog ... /SaveAs ...` export.
- [stable.csv](stable.csv), [resumed.csv](resumed.csv),
  [stable-gui-done.png](stable-gui-done.png),
  [cancel-state.png](cancel-state.png), and
  [resume-gui-done.png](resume-gui-done.png) show the GUI outcomes. The CSVs
  contain paths and hashes of disposable fixture files only.

The capture is observational. Sysmon ID 3 and a 128-byte packet prefix do not
show TLS plaintext, and neither source review nor one VM run can prove a
universal negative. The host machine's other network activity was not
attributed to GAMI Hash. The WebView2-absent and future-remediation retests
remain required.

Raw, unfiltered VM traces also contain unrelated Microsoft account and system
activity. A scan of the full Process Monitor CSV found 544 rows with email-like
text, 3,951 rows with account-related paths, and 265 rows with possible secret
labels; those are conservative pattern counts, not a finding that credentials
were disclosed. `.gitignore` excludes the raw traces and the mistaken initial
run CSV from Git. The filtered app-specific evidence and this report can be
reviewed in the repository; share raw traces only through an approved private
channel if an auditor needs them.
