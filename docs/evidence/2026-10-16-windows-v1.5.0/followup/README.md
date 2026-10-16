# Follow-up: decrypted requests from the signed v1.5.0 GUI

Tested 2026-10-15 23:49–23:57 UTC in the same disposable Windows 11 Pro VM
and signed GAMI Hash v1.5.0 installation described in the [initial report](../README.md).
The VM already contained WebView2 Evergreen 155.0.4283.60. The operator
opened the GUI, left it idle, completed a 514-file run, then cancelled and
resumed another run. The operator reported both runs finished. This capture
answers what the **attributed requests in this run** contained; it is not a
proof about all network behavior on every machine or release.

## Result

GAMI Hash's WebView2 process tree opened **11 TCP connections** to a temporary
inspection proxy. Sysmon process GUID ancestry linked the connections to
`GAMI Hash.exe` PID 1616 and its WebView2 children. Matching guest source ports
linked those connections to **13 decrypted HTTP requests**. `pktmon` recorded
packets in both directions for all 11 source-port tuples. The complete
redacted request list is [attributed-requests.json](attributed-requests.json);
[connection-correlation.json](connection-correlation.json) records the process
GUIDs, source ports, and packet counts. Unrelated Edge and Windows proxy
requests were excluded by process GUID and source port.

| Requests | Destination and path | What was sent |
| --- | --- | --- |
| 12 GETs | `substrate.office.com` `/profileb2/v2.0/me/V1Profile` and `/imageB2/v1.0/me/image/$value` | No request bodies. Each carried an `Authorization` header and an `X-AnchorMailbox` header. Header **values** are private and are absent from the repository. Responses were HTTP 200 for profile and 404 for image. |
| 1 POST | `edge.microsoft.com` `/componentupdater/api/v1/update` | A 5,675-byte JSON body containing browser component update checks and OS/hardware/runtime metadata. The URL also had update protocol query parameters. Response was HTTP 200. |

The account profile traffic is a concrete privacy concern: a claim that the
Windows GUI uses no accounts or sends no account-related data is unsupportable
for this VM run. The request bodies inspected here contained no selected
source-file contents. That limited finding does **not** establish that no
source-file data can ever leave on another code path or release. The capture
does not identify which internal WebView2 feature caused the account requests;
the hashing source code has no such request. It also does not show whether the
component updater downloaded or installed anything.

## Method and limits

The signed production build did not open DevTools with F12 or Ctrl+Shift+I.
Its pinned `go-webview2` loader passed an empty value for additional browser
arguments, overriding the temporary environment/registry NetLog setting; no
NetLog file appeared. We therefore used `mitmproxy` 12.2.3 on the host's
VMware-only address `192.168.247.1:8766`. A disposable CA certificate was
temporarily trusted inside the VM, and the `tech` user's Windows proxy was
pointed at that address. A separate `https://example.com/` control request
returned HTTP 200 through the proxy before the app run.

Sysmon IDs 1 and 3 identified the GAMI Hash process tree and its connections
to the proxy. For every attributed source port, the proxy recorded an HTTP
request and `pktmon` recorded traffic in both directions. The proxy's broader
log also contained Edge and other Windows traffic; timing alone would have
misattributed it. The analysis used source-port and process GUID matches.
This was a scoped TLS interception test; it did not inspect non-proxied
protocols, future traffic, or activity outside the capture window. No direct
Sysmon network event from `GAMI Hash.exe` itself appeared in this window.

After the capture, `ProxyEnable` was restored to `0`, the previous proxy
server value remained absent, and the temporary CA was removed from
`LocalMachine\Root`. The [cleanup result](cleanup.json) records those checks.
The proxy was then stopped. Raw proxy flows contain live authorization and
mailbox values and remain **local and private**, outside the repository.
Do not attach them to an issue, commit, or public report.

Local raw artifact hashes for controlled review:

| Artifact | SHA-256 |
| --- | --- |
| Host `mitmproxy` flow file | `eaff65a8969813618eebcd262d20bf1a21346280dc0ce4b2b360164a01aab387` |
| Filtered Sysmon JSON | `b5507e194b3b89a5c3b26bd818e8f9888346b0516af171c87ec6d70a0539e3a8` |
| VM `pktmon` ETL | `876912a0571428ca7771d20712aa0fdc8879a2616cd7e18afb971bb2ca2c80b1` |

## What can be changed

The v1.5.0 Windows GUI cannot honestly be certified as making zero outbound
requests. The first product step is to investigate why this WebView2 profile
accesses Microsoft account endpoints and to stop that behavior in the WebView
integration, then retest a newly signed build. Disabling app web-content
requests through `WebResourceRequested` is useful for the app's own content,
but it should **not** be assumed to cover WebView2's account and component
services. Microsoft documents controls for SmartScreen and custom crash
reporting; neither addresses every connection observed here. Browser flags
such as `--disable-background-networking` may help diagnose causes, but
Microsoft cautions against relying on flags as a production contract.

For an institutional guarantee of no *successful* outbound traffic, IT can
deny outbound networking for an isolated GAMI Hash environment and retest the
whole process tree. A global block on `msedgewebview2.exe` would also affect
other applications using WebView2, so it is not a suitable general desktop
policy. If the product must make no outbound **attempts**, the WebView2
integration needs a verified fix, or a GUI that does not depend on a networked
browser runtime. The separate Evergreen updater and installer also need their
own assessment. Relevant Microsoft references:
[WebView2 privacy](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy),
[request interception](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/webresourcerequested),
[browser flags](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags), and
[Edge Update policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies).

## Missing-WebView2 installer test remains open

The existing Windows 11 VM is unsuitable: WebView2 was present before GAMI
Hash installation, and a snapshot-backed uninstall attempt failed. Source
inspection shows the NSIS macro checks WebView2's EdgeUpdate registry version
and, when absent, runs a **bundled online Evergreen bootstrapper** with
`/silent /install`. The macro does not check the bootstrapper's exit status.
That establishes intended installer logic, **not observed behavior** on a
machine without WebView2. The corresponding source is
`build/windows/installer/project.nsi` and the pinned Wails
`pkg/buildassets/build/windows/installer/wails_tools.nsh`.

To close the gate, provision a separate clean Windows VM whose WebView2
absence is verified before GAMI installation, snapshot it, disconnect its
network, and run the signed v1.5.0 installer while recording process and
network events, installer logs, exit status, and GUI launch. Restore the
snapshot, connect the network, and repeat. Record whether the runtime was
installed, where it came from, and what the user saw in each case. Use a
Windows image that does not already include WebView2; do not remove shared
runtime files from the current Windows 11 VM and mistake that for a clean
installation. There was insufficient free local disk space for a second
Windows VM during this follow-up, so this branch was not run.
