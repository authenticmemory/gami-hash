# Slice 2 network attribution

Date: 2026-10-17

Artifact: development-signed `0.1.2.0`, SHA-256
`e1216bf45ca26505bc45aecef6ca1965932d8fa16630c8c869f20f9603f07347`.

Environment: the same disposable Windows 11 x64 VMware guest and standard
`gami_runner` account used for Slice 1. The package manifest declared no
network capability.

## Controlled result

The spike launched its own executable with
`--appcontainer-network-probe`. Sysmon linked that child to the packaged host.
The child remained alive after publishing its result so it could be included
in process attribution.

The test attempted DNS and TCP/UDP over IPv4/IPv6 to loopback, a private
address, and public addresses. PktMon captured the same window. Existing WFP
connection/drop auditing was preserved and queried rather than reconfigured.

- DNS returned `no such host`.
- Private/public IPv4 TCP returned Windows socket access-denied errors.
- IPv6 private/public routes were unreachable.
- UDP API writes returned success, but PktMon recorded the IPv4 private/public
  datagrams and IPv4/IPv6 loopback datagrams as drops.
- WFP recorded `5152`/`5157` blocks for private/public TCP and UDP.
- WFP allowed the probe's loopback attempts at one filtering layer (`5156`),
  but PktMon recorded the packets as drops and the listeners received none of
  the probe's ten-byte payloads.
- The listeners subsequently received all four outside-boundary positive
  controls: TCP4, TCP6, UDP4, and UDP6. This proves the listeners and capture
  window were functioning.

Whole-tree WFP correlation found four WebView2 network-service attempts, all
TCP loopback to port 80 (two IPv4 and two IPv6). PktMon recorded the IPv4
attempts and resets as drops. No WebView2 descendant attempted a private or
public destination during the controlled launch window, and no app-owned
packet was delivered.

## Gate

**PASS for the tested Slice 2 window.** The explicit negative controls were
not delivered, the outside-boundary controls were delivered, and all observed
WebView2 network activity was loopback-only and dropped. This is development
prototype evidence, not signed-release acceptance or a claim about all future
WebView2 runtime versions.

The next permitted step is Slice 3: replace only the spike bridge with the
existing Phase 2/3 broker and produce one oracle-matching local manifest. The
legacy Wails path-based picker/backend remains rejected.
