# WebView2 inside AppContainer Slice 3 storage evidence

Date: 2026-10-18

Environment: disposable Windows 11 x64 VMware guest, standard
`Gami-Hash-VM\gami_runner` account.

Artifact: development-signed `0.1.5.0` WebView2 AppContainer spike.

SHA-256:
`a516e72581987cdd8779e256431fb73d0365393138f2caeb9b5bd34c0352b475`

## Functional result

- The unchanged WebView2 frontend rendered and completed its three-step flow.
- Source: `C:\projects\gami-hash\slice3-fixture`.
- Destination: `C:\projects\gami-hash\slice3-output`.
- The native spike bridge retained picker-returned WinRT `StorageFolder`
  authority and invoked the existing Phase 2/3 broker and contained worker.
- The completed screen reported two files and 35 bytes recorded.
- Output: `checksums_slice3-fixture_2026-10-17.csv`.

## Manifest verification

| Relative path | Bytes | Expected and recorded SHA-256 |
| --- | ---: | --- |
| `alpha.txt` | 18 | `cded0205689ed45801954c4712ac1052d5427348af920f4009fe4ed4f71f57a3` |
| `nested/beta.txt` | 17 | `552d934fc5b76c8c526e67e7b84d343c3df3f0bc34b00c0b7a9a0d328f8d20b6` |

The expected hashes were independently calculated from the exact fixture
bytes written by Windows PowerShell: UTF-8 BOM, fixture text, and CRLF.

## Assurance capture

A second run used eight 256 MiB local files. Capture window:
`2026-10-18T01:44:54.7677162Z` through
`2026-10-18T01:47:25.7152820Z`. The contained worker appeared at
`2026-10-18T01:46:45.2404801Z`, proving the hash operation fell inside the
window.

The live collector observed nine processes:

- one Wails host;
- six WebView2 processes: browser, crash handler, GPU, network service,
  storage service, and renderer;
- one `GamiHashContainedWorker.exe`; and
- its `conhost.exe` child.

Every observed process returned `TokenIsAppContainer=true`, with no token read
errors. No full-trust helper appeared.

The loopback listener received all four outside-boundary positive controls:
TCP/UDP over IPv4 and IPv6. PktMon recorded no app-owned outbound packet to a
monitored loopback, private, or public target. The only record carrying an
observed app PID was an inbound, nondestined ARP frame dropped by Windows.

The resulting manifest contained the expected eight paths and exactly
2,147,483,648 bytes. Its SHA-256 was
`640158d9672c4fd3783e8eb677c5d803a57b805879c7cb1bec2c012cbacf4491`.

## Decision

The brokered local-fixture behavior **passes**. This proves that the existing
frontend can use the existing storage broker inside the capability-free
AppContainer without reverting to path-based filesystem authority.

The Slice 3 local-fixture assurance gate **passes**. Together with Slices 1
and 2, this passes the WebView2-inside-AppContainer feasibility assessment for
the tested development artifact.

At the time of this assurance capture, resume and **Open folder** were still
prototype gaps. They did not invalidate the bounded local-fixture feasibility
result. The follow-up below tested their active-session implementation. This
remains development evidence, not signed-release evidence.

## Bridge completion follow-up

Development build `0.1.6.0`, SHA-256
`29687ebc84cdc9c0c4dbc597bbdd85053e06709b7e0c29fc44c5204e9d2cd62d`,
completed the active-session bridge behavior on the same VM:

- the user canceled an eight-file, 2 GiB run after progress began;
- the stopped screen offered **Continue now**;
- the contained worker resumed from its brokered checkpoint and completed;
- **Open folder** invoked Windows Launcher with the retained destination
  `StorageFolder`, and Explorer opened the output directory.

This closes cancellation, same-session resume, and **Open folder** for the
prototype bridge.

## Restart-resume and lifecycle follow-up

Development build `0.1.15.0`, SHA-256
`6ea9bc2688bf819f522dde5e3f831c9096451523742fc557f241a21dc7f19694`,
passed the restart-resume and relaunch checks on the same VM:

- fixed-name `FutureAccessList` grants restored the source and destination
  `StorageFolder` objects after process exit; the bridge reclassified both
  objects before restoring authority;
- the interrupted-run screen derived its count from the persisted CSV and
  displayed **8 files recorded so far**, rather than the earlier placeholder
  zero;
- continuing without reselecting either folder reached the resume review and
  completed the existing eight-file, 2 GiB manifest;
- closing the window completed adapter shutdown and terminated the packaged
  host through the native bridge; the bounded network-probe child exited
  shortly afterward; and
- a new package activation created a fresh host and rendered the restored
  interrupted-run state.

The explicit native termination is prototype-specific lifecycle plumbing. It
was required because Go's `os.Exit` and `syscall.ExitProcess` calls returned
inside this AppContainer instead of ending the process. Productization must
retain the close/relaunch regression gate and replace the spike bridge naming
and diagnostics with production-owned equivalents.
