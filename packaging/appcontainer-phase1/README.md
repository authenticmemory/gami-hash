# Phase 1 AppContainer feasibility probe

This is a **disposable test app**, separate from the released GAMI Hash GUI.
It answers whether a packaged native Windows process can use brokered folders
and remain without network capabilities. It does **not** implement GAMI's CSV
format, consent flow, or Go hashing engine. Version 0.1.1.0 added a diagnostic
cancel/checkpoint path; version 0.1.2.0 bundled the signed v1.5.0 Go CLI solely
to test direct path access under the same AppContainer token.

The [manifest](AppxManifest.xml) declares `uap10:TrustLevel="appContainer"`,
`Windows.PartialTrustApplication`, and no capabilities. It has no full-trust
or browser entry point. That is a configuration claim until process tokens are
checked at runtime.

## Probe operations

1. Pick a source folder and output folder with Windows `FolderPicker` and
   persist their `FutureAccessList` tokens. The picker may access a provider
   while browsing; this probe does not implement the product's consent UI.
2. Launch the same executable as a worker child. The worker records its PID and
   `TokenIsAppContainer` value.
3. Attempt TCP and UDP to loopback, a private test address and a public test
   address, plus a DNS lookup. Record Winsock results. A timeout or refused
   connection is **inconclusive**, not proof of sandbox denial. The VM test
   must confirm denial from token/policy and packet evidence.
4. Reopen the picked folders from persisted tokens, recursively enumerate and
   SHA-256 stream files via WinRT, and separately try path-based enumeration
   and file opening. Save a **diagnostic** three-column CSV in the selected
   output. This is not GAMI's five-column manifest.
5. Relaunch and run the worker again to check persisted access. Repeat on
   local NTFS, UNC/mapped SMB, and an online-only cloud folder, with both local
   and remote destinations. Record unavailable/revoked cases.

The worker deliberately refuses an output path lexically below the source,
but this is **not** the product's canonical path or alias security check.
Use only disposable fixture data.

## Build and test status

Build with `./build-probe.ps1 -Sign` on a Windows SDK + MSVC host. The script
compiles C++/WinRT, packages with `MakeAppx`, verifies an unpacked round trip,
then signs with a short-lived **development certificate**. It writes a unique
output directory under `build/bin/appcontainer-phase1/`. Temporary private
keys/PFX files were removed after the final Phase 1 package was signed and
must never be published.

First signed artifact, built 2026-10-16: MSIX SHA-256
`e2120a402ca29f58c73226a76ac50c9045cf29b5313ff1bbf08f0e59dc622554`;
public certificate SHA-256
`6d5399f25f6f87764db71b3b1f201942bb54efb0a42872a77d91f11a956b1446`.
The exact package and certificate are staged in the disposable VMware VM under
`C:\Users\Public\Documents\GamiPhase1Probe`. The test certificate is not
publicly trusted. Windows rejected unattended install with `0x800B0109` until
its public `.cer` is trusted in the VM's Local Machine Trusted People store.
The public certificate was imported interactively into `LocalMachine\TrustedPeople`
and the package installed for the VM test account. The account has administrator
rights; a later standard-user retest is required by the Phase 0 matrix.

After trust is established, `install-in-vm.ps1` installs the package for the
test account and records an `install-result.json`. `collect-in-vm.ps1` records
the installed package identity, running probe processes, and the worker status
file. Retain raw process/network traces privately if they contain account or
provider metadata.

| Gate | Current result |
| --- | --- |
| Native compile and MakeAppx schema validation | **PASS** on build host |
| Package unpacked executable/manifest round trip | **PASS** on build host |
| Development signature applied | **PASS** by SignTool; certificate trusted only in disposable VM |
| VM install and launch | **PASS** for this VM/account; unattended install first failed with `0x80070005`, interactive install succeeded |
| GUI and worker live AppContainer tokens | **PASS** for the 0.1.1.0 run; both tokens independently queried and Sysmon linked the worker to the GUI |
| Direct TCP/UDP/DNS/loopback blocked | **PARTIAL**: WFP attributed private/public IPv4 blocks to the worker; PktMon showed its UDP packets dropped. IPv4/IPv6 loopback did not reach listening controls, while unsandboxed controls did. Off-loopback IPv6 lacked a route; comprehensive network assurance remains open. |
| Local picker and output | **PASS** for five-file NTFS fixture via WinRT; all SHA-256 values matched independent fixture inventory |
| Ordinary path-based traversal | **FAIL** with access denied before the first file; current Go engine has not been run in the container |
| UNC/mapped SMB picker/output | **PASS** for same-VM UNC/`Z:` and one authenticated separate-host UNC case. After removing the host share, a saved-token retry failed with a missing-file error; remap/denial and recovery UI remain untested. |
| Cloud picker/output | **PASS** for 500 files through Google Drive for desktop's streamed `G:` drive; independent post-run hashes match. The user confirmed the CSV appeared on Google's website. Initial per-file hydration state and provider network attribution remain unverified. |
| Persisted token after restart | **PASS** for same-account local fixture; missing remote share returned an error; revoked-grant recovery remains untested |
| Diagnostic cancel, close, reopen, resume | **PASS** for generated 1,024-file/256 MiB local fixture: resumed from 64; independent CSV comparison found zero missing, duplicate, size, or SHA-256 mismatches. Changed-file and moved-root semantics remain untested. |
| Go worker/path access equivalence | **FAIL** for direct paths: bundled signed v1.5.0 CLI ran as an AppContainer child, exited 1 with `invalid root folder: Access is denied.`, and wrote no CSV. The same picked root produced five correct WinRT hashes. |

The detailed [VM run record](../../docs/evidence/2026-10-16-windows-appcontainer-phase1/README.md)
contains the artifact identity, observed results, and outstanding tests. The
Phase 1's [stop/go decision](../../docs/decisions/0001-windows-appcontainer-storage-adapter.md)
is **stop direct-path GUI migration**. The signed Go CLI test confirms the
current path-based engine cannot simply receive a picker path. Phase 2 must
prove a contained storage adapter; network, provider, standard-user, and
release assurance gates remain open.
