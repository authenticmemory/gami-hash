# WebView2 inside AppContainer spike

This development-only package implements the bounded three-slice
[feasibility assessment](../../docs/WINDOWS-APPCONTAINER-WEBVIEW2-FEASIBILITY.md).
It reuses the current embedded frontend and Wails host under a separately
named AppContainer identity. It is not a release candidate.

Build an unsigned structural-check package:

```powershell
./packaging/appcontainer-webview2-spike/build-spike.ps1 `
  -Go 'C:\path\to\go.exe' -Version 0.1.0.0
```

For a VM-installable package, pass the thumbprint of a development
code-signing certificate whose subject is exactly
`CN=GAMI Hash WebView2 AppContainer Spike`. Trust that certificate only in the
disposable VM.

The signed build directory contains `development-certificate.cer` and
`install-in-vm.ps1`. Copy that directory to the VM and run the installer as
the standard test user. It imports only the public certificate into that
user's `TrustedPeople` store before installing the package.

After installation, start **GAMI Hash WebView2 Spike**, leave it at the welcome
screen, and run:

```powershell
./packaging/appcontainer-webview2-spike/inspect-process-tree.ps1 -DurationSeconds 30
```

Run the repository's existing Sysmon/process-creation capture over the same
window. The polling script records live descendants and their tokens, but it
cannot prove that a short-lived or reparented crash-handler process never
existed. Reconcile every process-creation event rooted at the spike host with
the token inventory before passing the gate.

Capture the welcome screen, then click **Choose folder**. A rendered picker or
a handled picker error demonstrates that the real Wails JavaScript bridge was
invoked; a static screenshot alone does not.

Slice 1 passes only when the original UI renders, the bridge responds, and
every observed host/browser/renderer/GPU/utility/crash process has
`isAppContainer: true`. Stop on a blank control, initialization failure,
uncontained child, full-trust helper, or any need to disable sandboxing.

The manifest declares no capabilities. This is necessary but does not prove
network non-delivery. Follow the process-token, controlled-network, and
brokered-storage gates in the feasibility assessment and preserve durable
results under `docs/evidence/`.
