# WebView2 inside AppContainer Slice 1 evidence

Date: 2026-10-17

Environment: disposable Windows 11 x64 VMware guest, standard
`Gami-Hash-VM\gami_runner` account.

Artifact: development-signed `0.1.0.0` WebView2 AppContainer spike.

SHA-256:
`889c089b7b5b9e84a92940b7ddff785773d502234ddf523587c3991c220e7866`

Package full name:
`AuthenticMemory.GAMIHash.WebView2AppContainerSpike_0.1.0.0_x64__49hsk8vwag5ka`

WebView2 runtime: `155.0.4283.60`.

## Observed result

- The original embedded Wails frontend launched and rendered.
- **Choose folder** and **Choose where to save** invoked the real host-side
  dialogs, proving that the Wails JavaScript bridge responded.
- The legacy path-based folder dialog reported access denied for
  `C:\Users\gami_runner\Desktop`.
- The legacy save dialog opened, but **Save** did not complete the selection.
  This backend is not the intended brokered storage implementation.
- A corrected 30-second live inventory found the host, WebView2 browser,
  crashpad handler, GPU, network service, storage service, and renderer.
  `TokenIsAppContainer` was true for all seven processes.
- Every WebView2 process used the package-local profile under
  `AppData\Local\Packages\...\AC\AuthenticMemory\GAMIHashWebView2Spike`.
- Sysmon recorded the host and seven WebView2 process creations. All WebView2
  events were rooted at the spike's browser process. The extra event was a
  later GPU-process start that had exited before live-token collection.

## Live token inventory

| Role | PID | Parent PID | AppContainer |
| --- | ---: | ---: | --- |
| Wails host | 1324 | 4440 (`explorer.exe`) | Yes |
| WebView2 browser | 1520 | 1324 | Yes |
| Crashpad handler | 8944 | 1520 | Yes |
| GPU process | 8224 | 1520 | Yes |
| Network service | 5332 | 1520 | Yes |
| Storage service | 9424 | 1520 | Yes |
| Renderer | 5384 | 1520 | Yes |

## Evidence limits and decision

The render and bridge-invocation questions pass. The live process tree is
contained for every observed process. Sysmon closes the process-lineage gap,
but the exited GPU process cannot be queried retrospectively for its token.
Capture that replacement process during the controlled restart in Slice 2.

Slice 1 is therefore **provisionally passed for continuing to the network
negative-control slice**. It is not release evidence and establishes no
network claim. The legacy Wails path-based storage behavior does not pass and
must not be reused for Slice 3.

Raw capture hashes retained in the local build evidence:

- `webview2-spike-process-tree-30s.json`:
  `28a22630565efb9f838eb9d90d3a1145f25e091f3c5288506e55cdfad389a19e`
- `webview2-spike-sysmon-processes.json`:
  `4621e50fd054b14ba69dbf6565b723828bbecef92412647830bfec9b75da4586`
