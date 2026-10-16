# Phase 1 AppContainer probe: first Windows VM run

Status: **Phase 1 direct-path gate failed; product assurance remains open**.
Observed on 2026-10-16 in the disposable Windows 11 VMware VM. This is an
independent C++ test app, not a build of the product GUI. The 0.1.2.0 variant
bundled the signed v1.5.0 Go CLI solely for the contained-path test. Raw VM
logs remain outside this evidence directory; temporary development signing
keys were removed from the ignored build folders after the final test package
was signed.

## Artifact and environment

| Item | Observed value |
| --- | --- |
| MSIX SHA-256 | `e2120a402ca29f58c73226a76ac50c9045cf29b5313ff1bbf08f0e59dc622554` |
| Package | `AuthenticMemory.GAMIHash.AppContainerProbe_0.1.0.0_x64__tbw3fy9pb0hh8` |
| Installed manifest SHA-256 | `4756ae2758f62f0dc3bd14a749215dcbec496429144b86988d69c74061febf5b` |
| Package capabilities | None declared; `uap10:TrustLevel="appContainer"`; no full-trust entry point |
| Development certificate SHA-256 | `6d5399f25f6f87764db71b3b1f201942bb54efb0a42872a77d91f11a956b1446` |
| Account | Disposable administrator account; standard-user test remains open |

The first install attempt rejected the untrusted development certificate
(`0x800B0109`). After the public certificate was imported into the VM's Local
Machine Trusted People store, interactive installation succeeded. A
noninteractive deployment attempt returned `0x80070005`; this is an installer
test limitation, not evidence that ordinary users can install the final app.

## Local fixture run

In the **first 0.1.0.0 run**, the GUI process (PID 8104) was independently inspected through its Windows
process token: `TokenIsAppContainer=true`. It launched worker PID 11208, which
self-reported `AppContainer=1`. We have not independently captured the short
lived worker token or a complete child-process tree.

The user picked a local five-file source folder and a separate output folder.
The worker reopened both picker tokens and streamed all five files through
WinRT storage objects: 65,577 bytes. The diagnostic CSV's paths, byte counts,
and SHA-256 values matched the independently generated fixture inventory,
including a Unicode filename and a 64 KiB binary file. This tests basic
functionality only; the diagnostic CSV is not the product's five-column CSV.

The worker's ordinary `std::filesystem::recursive_directory_iterator` failed
with `Access is denied` before the first file. The current Go engine uses
path-based enumeration/opening, so giving it a selected path was not a proven
solution at this point. The later 0.1.2.0 signed Go CLI test below confirmed
direct path access fails. Phase 2 must prove a contained storage-object/stream
adapter before reusing the engine.

**Source-write assurance is a separate unresolved gate.** Microsoft's
[folder-picker example](https://learn.microsoft.com/en-us/windows/uwp/files/quickstart-using-file-and-folder-pickers)
says a picked folder grants the app read/write access to its contents. This
probe only read the source; it did not attempt a write. The current picker
grant therefore does not support a categorical statement that the AppContainer
*cannot* change source files. Phase 2 must define an OS-enforced read-only
input boundary or explicitly limit the claim to what the audited code does,
then run a disposable source-write negative control.

After closing and reopening the GUI (new PID 7112), the user ran the worker
without picking either folder again. The new worker (PID 7088) reopened both
saved tokens and again enumerated five files/65,577 bytes and wrote the
diagnostic CSV. This supports persistence for the same account and folders;
revoked grants and remapped/remote paths remain untested.

## SMB loopback pretest

An authenticated Windows SMB share, `\\GAMI-HASH-VM\GamiPhase1Loopback`,
was created inside the disposable VM. This is a UNC/SMB **loopback** test, not
a separate remote server. The VM account could independently enumerate the
share's source and output folders, and its five source hashes matched the
local fixture before the probe run.

The contained GUI selected both UNC folders with `FolderPicker`. Worker PID
436 self-reported `AppContainer=1`, reopened the selected tokens, streamed
five files/65,577 bytes, and wrote `phase1-probe.csv` through WinRT to the
UNC output. All five CSV paths, byte counts, and hashes matched the fixture.
Ordinary path-based traversal failed before the first file with `Network
access is denied`. This strengthens the case for a storage-object adapter;
it does **not** prove the behavior of a share on another computer, mapped
drives, disconnections, or institutional authentication.

The same loopback share was also mapped as `Z:` in the interactive VM account.
The GUI picked `Z:\source` and `Z:\output`; worker PID 2204 self-reported
`AppContainer=1`, streamed five files/65,577 bytes, and wrote the CSV to
`Z:\output`. Independently comparing the saved CSV against the fixture found
all five paths, sizes, and SHA-256 values identical. Direct path traversal
again failed with `Network access is denied`. This tests mapping of the
same-VM share only; a drive remap or separate server remains open.

## Separate-host SMB test

With user approval, a temporary encrypted SMB share was created on the Windows
host at `\\192.168.247.1\GamiPhase1Remote`, backed by a five-file fixture. It
uses a dedicated temporary host account and a firewall rule restricted to the
VM's current `192.168.247.128` address on VMware VMnet8. The VM first read all
five source files through SMB; paths, sizes, and SHA-256 values matched the
host fixture inventory.

The contained GUI then picked the share's UNC `source` and `output`. Worker
PID 4060 self-reported `AppContainer=1`, reopened both picker tokens, streamed
five files/65,577 bytes, and wrote the diagnostic CSV on the host share. An
independent comparison of that CSV found all five rows and hashes identical
to the fixture. Ordinary path traversal again failed with `Network access is
denied`. This is a **real two-machine SMB functional pass** for one account,
share, and network state. After the host share was removed, the user ran the
worker again without repicking the persisted folders. Worker PID 10652
self-reported `AppContainer=1` and returned WinRT HRESULT `2147942402`
(`The system cannot find the file specified`). No successful enumeration or
output was reported. This is a useful missing-share failure case, not a
complete test of revocation, path remapping, or recovery UX.

The host cleanup script reported removal of the temporary share, firewall
rule, local account, and secret. A separate host check found all four absent.
The guest cleanup script removed the `R:` mapping and stored host credential;
a guest check found neither afterward. The five-file fixture and private
result logs remain in the ignored build directory. Denied access, remapped
paths, standard-user accounts, and other SMB server configurations remain
open.

The private disconnected-run JSON has SHA-256
`b9c5b9d20640e4cfad3d318750cd625c50bd487969ac22e23b3c24b0a46b550d`;
the guest cleanup-verification JSON has SHA-256
`a8db02bacdd163a46a6568cae17950c1c0303780bc3d996e25a483169e8e821c`.

## Google Drive for desktop streaming test

The user installed Google Drive for desktop in the VM and exposed a disposable
source and separate destination at `G:\My Drive\gami-test` and
`G:\My Drive\gami-test-destination`. The provider's virtual drive is a
filesystem path; the original `https://drive.google.com/...` folder URLs alone
would not have been selectable by this prototype. A pre-run metadata-only
inventory found 500 ordinary text files totaling 940,051 bytes plus a hidden
`desktop.ini`. It did not open file contents, and the Windows attributes were
`Normal`, so this inventory does not independently prove each file's cache or
online-only state.

The user confirmed that Drive for desktop was set to **Stream files**, that
the source folder had not been marked **Available offline** before the run,
and that `phase1-probe.csv` appeared in the destination on drive.google.com
after synchronization. These are user-observed provider settings and remote
output confirmation, not an independent pre-run cache-state capture or a
provider network trace.

Worker PID 444 self-reported `AppContainer=1` and eventually completed after
several minutes while Drive for desktop was syncing. It reopened both picker
tokens, streamed 500 files/940,051 bytes through WinRT, and wrote a diagnostic
CSV to the Drive destination. The CSV has 500 distinct paths matching all 500
nonhidden source files. A separate full-trust post-run read of every source
file found **zero size or SHA-256 mismatches** against the CSV. The hidden
`desktop.ini` was not included. Direct path traversal failed before the first
file with `Access is denied`.

The probe GUI briefly showed a new worker PID alongside **stale status from
the preceding mapped-drive run** while the cloud worker was still active.
Process inspection confirmed that PID 444 remained alive and no cloud CSV
existed at that point. The GUI's status file was overwritten only when the
worker finished. The probe therefore needs a per-run status identifier and
explicit pending/completed state before its UI can be reused in a product.
The cloud result establishes this provider's functional read/write path for
these 500 files, with user-confirmed upload on Google's website. Initial
per-file online-only state and process-attributed provider-versus-app network
traffic remain unverified.

The private cloud CSV has SHA-256
`7d87f2c1028ff7d72156113dfb613d397c2d90870100b900b41a486878bc1016`;
the independent comparison JSON has SHA-256
`6fa9deb0f60708ec10daa96b670cb72b455e8786bb090e448c5c2f56258e19ff`.

## Network probe

### Updated 0.1.1.0 process and network attribution run

A separately signed prototype update was installed in the same VM. Its MSIX
SHA-256 is `3d18cfed25b845cde5c32b63a221593bb3b98807992b3cf430b57b911eb42552`;
its installed manifest SHA-256 is
`f1f26138204ce321a4e7a014c815c27a8eee3cb46236d0d8c86904038df4f743`.
It added a diagnostic Cancel/checkpoint path and IPv6 socket attempts. The
package still declares no network capabilities. These results concern this
prototype version, not the released GUI.

For the 2026-10-16 10:11:40–10:13:49 UTC capture, an independent process-token
query observed GUI PID 5508 and worker PID 1944 with
`TokenIsAppContainer=true`. The worker's parent PID was 5508. Sysmon process
creation events linked their process GUIDs and showed one worker child of the
GUI and no observed children of that worker in the capture interval. The
worker hashed the five-file local fixture and wrote five distinct diagnostic
CSV rows; every path, size, and SHA-256 matched the independent fixture.

Windows Filtering Platform (WFP) Security events `5157`/`5152` identified
worker PID 1944 and the prototype executable for four blocked off-loopback
IPv4 attempts: TCP and UDP to `192.168.247.1`, and TCP and UDP to `1.1.1.1`.
The recorded filter origin was `UWP Default Outbound Block Rule`. PktMon
recorded the two one-byte off-loopback UDP packets as inspection drops with
no observed NIC appearance. [Microsoft documents the WFP audit events](https://learn.microsoft.com/en-us/windows/win32/fwp/auditing-and-logging)
and [event 5157's application/PID fields](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-5157).

IPv4 and IPv6 loopback require a finer reading. WFP recorded `5156`
**permits** for the worker's TCP/UDP loopback attempts at one layer, but
PktMon recorded the worker's TCP SYN and one-byte UDP packets as later
receive/inspection drops. The listening process received **none** of those
worker attempts. Immediately afterward, an unsandboxed PowerShell control
connected over both TCP families and delivered four UDP bytes over each
family to the same listeners; the listener logged all four controls. Thus
`5156` alone would have been misleading here. The worker reported TCP
loopback timeouts and successful UDP `sendto` calls, consistent with the
packet/receiver evidence. IPv6 private/public attempts returned `WSAENETUNREACH`
(10051); the VM had no usable route to those addresses, so this run does not
separately prove an off-loopback IPv6 sandbox block.

Sysmon event `3` also recorded the worker's **attempted** off-loopback UDP
destinations even though WFP blocked them. A Sysmon network event cannot be
read as proof that the packet left the machine. Sysmon event `22` recorded an
`example.com` query for the worker with failure status; there is no evidence
of a successful DNS response to the worker in this capture. Other VM processes
generated SMB packets to the host during the capture; they are outside the
observed probe process tree and do not establish app-owned traffic.

Raw captures remain private in the ignored build directory. Their SHA-256
values are: PktMon ETL
`7e135d92b12e3f609f8cbda19290bcfe3afd0519fb5f0239a1056c7f1a876b9f`,
PktMon text
`20cf2bdbb72f95b705b03f885b6507aa482bfd8eb9044d7c4b0e017d9c50e3c8`,
WFP event JSON
`b0c5e48ee0997df907ca1f1b0544a910fe13a34b9b04e072212fe1ac7f80471e`,
Sysmon event JSON
`b863c71dce55bfba9248a4537ec0418f674cdfd8e37891d3253037ab3198389a`,
and independent token JSON
`dd628bf8b7a4f161a6d54bd2f7c37a235d949a0b4cfc626ed3966de05b252f49`.
The audit settings were restored to their observed pre-capture `No Auditing`
state by the stop script. An independent check at 10:21:08 UTC confirmed both
`Filtering Platform Connection` and `Filtering Platform Packet Drop` again
reported `No Auditing`. Its private JSON record is
`network-audit-inspection-after.json` in the ignored build directory.

### Diagnostic cancel and resume

The 0.1.1.0 probe used a separate, generated 1,024-file NTFS fixture: each
file was 256 KiB, for 268,435,456 bytes total. The first worker was cancelled
after 64 files (16,777,216 bytes) and retained its checkpoint. After closing
and reopening the GUI, the next worker reported `Resumed completed files=64`,
then `WinRT enumeration files=1024 bytes=268435456`, and wrote its CSV.
An independent full-trust verifier hashed every source file and compared the
resulting CSV: 1,024 rows and 1,024 unique paths, with zero missing, extra,
duplicate, size, or SHA-256 mismatches. The CSV SHA-256 was
`4229c904b5b5682b3b94711e122c29ab27255d8ea022eda94858f849ac4b211f`.
The private `resume-verification.json` records these counts. This checks the
probe's simple same-folder checkpoint, not the released engine's changed-file,
moved-root, or error semantics.

### Signed Go CLI path comparison and Phase 1 stop decision

Prototype 0.1.2.0 bundled the installed, signed v1.5.0 CLI (`gami-hash
v1.5.0`; original executable SHA-256
`119921fa70185f18b56c138c15d69c6a15e5bdeefd8adf32e483493b247a1569`).
The probe MSIX SHA-256 is
`d61067a879a4b96d668e4e536133a4b96496ca4c42e55c1d50d930bc05b1e595`;
the installed manifest SHA-256 is
`63219fe64336f165bfc123c47a741d14f1e6edb8a94fee73768abd58c63c5827`.
It used the already trusted disposable test certificate and still declared no
network capabilities.

At 10:25 UTC, the GUI PID 6580 launched worker PID 8172, which launched the
signed Go CLI PID 6720. The worker queried the suspended Go child's token and
reported `AppContainer=1` before resuming it. Sysmon process-creation events
independently linked all three PIDs and the packaged executable path. The
picked local source yielded five WinRT CSV rows; independent comparison with
the five-file fixture found zero path, size, or SHA-256 mismatches. Ordinary
C++ path traversal failed before the first file. The Go child exited 1, made
no output CSV, and its private diagnostic log said `error: invalid root
folder: Access is denied.` The log SHA-256 is
`b5d028d36c27a9520023377ce482c555ccc86157c7df04556cc51eb26fa23ca2`.
The private `go-child-inspection.json` records the package, binary hashes,
Sysmon parentage, and absent Go output; `local-probe-0.1.2.0.csv` records the
successful WinRT path.

This is a **failed direct-engine gate**. The [architecture decision](../../decisions/0001-windows-appcontainer-storage-adapter.md)
stops a direct-path GUI migration and requires a contained storage adapter in
Phase 2. It does not declare the future GUI ready or establish complete
network silence for every supported Windows configuration.

### Initial packet probe

| Attempt | Worker result | Interpretation |
| --- | --- | --- |
| TCP private address | `WSAEACCES` (10013) | Direct connection denied in this run. |
| TCP public address | `WSAEACCES` (10013) | Direct connection denied in this run. |
| TCP loopback | timeout (10060) | Inconclusive; no listener was established. |
| UDP loopback/private/public | `sendto` returned 1, error 0 | API accepted the one-byte sends. Private/public datagrams were later observed as drops, below. Loopback remains unmeasured. |
| DNS `example.com` | 11001 | Lookup failed; this alone does not establish a network boundary. |

A second worker run was bracketed by Windows PktMon capture. Its two filtered
one-byte UDP sends appeared as **`Inspection drop`** at TCP/IPv4 component 13:
`192.168.247.128:53644 -> 192.168.247.1:9` and
`192.168.247.128:53645 -> 1.1.1.1:53` at 09:00:41 UTC. There were no NIC
appearances for those two packet groups. At 09:00:53 UTC, an unsandboxed
PowerShell positive control sent nine bytes to `1.1.1.1:53`; PktMon recorded
that datagram at Ethernet components 8, 4, and 1. The capture logged zero
lost events. Thus, in this specific run, `sendto` success did **not** mean the
worker's two tested datagrams escaped the VM network stack. PktMon's packet
record does not itself carry a PID; destination, length, sequence, and timing
correlate it with the worker log. Raw ETL/text trace and timing markers are
retained privately under the ignored build directory, not committed.
The private ETL SHA-256 is
`a9c3ce0bd52a21a14b6349b49078f0db42b52ca00820917ef830d999afebd179`;
its converted text SHA-256 is
`2885c2150cee122a23f7b8b9f083718107a770554e1fdb596fd417b6068c8ee6`.

This resolves the two filtered off-loopback UDP destinations for this run,
but not loopback, IPv6, every possible route/protocol, or process attribution
at the Windows Filtering Platform layer. A release claim still needs complete
process-tree, packet, and policy verification. [Microsoft describes AppContainer
network isolation](https://learn.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation)
as capability based, and [PktMon's capture modes](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/pktmon-start)
include both flow and drop observations. The manifest by itself is not runtime
proof.

## Tests still required for the adapter and release

1. Test revoked persisted grants and recovery UX after a missing or moved
   folder. A removed SMB share produced an error, but the prototype has no
   recovery flow.
2. Repeat process-tree and WFP/packet tracing on the implemented product;
   route off-loopback IPv6 and test DNS and other relevant network paths.
3. Test denied and remapped SMB paths and a standard-user account. One
   authenticated separate-host SMB case passed; a removed share failed with
   an error above.
4. Independently verify initial per-file cloud hydration state; repeat with
   cached files and capture provider-driven transfers separately from app
   sockets. Add other named providers before claiming their support.
5. Run the contained adapter under a standard-user account and compare its
   output with baseline CLI hashes and resume semantics. Direct use of the
   signed Go CLI already failed as recorded above.

Phase 1 reached its planned **stop** decision for direct-path migration. The
listed tests remain necessary before any adapter or released GUI can be
certified. No claim about the released v1.5.0 GUI changes as a result of this
prototype.
