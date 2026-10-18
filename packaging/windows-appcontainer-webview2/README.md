# Windows WebView2 AppContainer package

This production-owned package is based on the bounded three-slice
[feasibility assessment](../../docs/WINDOWS-APPCONTAINER-WEBVIEW2-FEASIBILITY.md).
It reuses the current embedded frontend and Wails host under a separately
named AppContainer identity. Release acceptance is tracked separately.

Build an unsigned structural-check package:

```powershell
./packaging/windows-appcontainer-webview2/build-package.ps1 `
  -Go 'C:\path\to\go.exe' -Version 1.6.0.0
```

For a VM-installable package, pass the thumbprint of a development
code-signing certificate whose subject is exactly
the `Publisher` passed to the build. Trust development certificates only in a
disposable VM.

The signed build directory contains `development-certificate.cer` and
`install-in-vm.ps1`. Copy that directory to the VM and run the installer as
the standard test user. It imports only the public certificate into that
user's `TrustedPeople` store before installing the package.

After installation, start **GAMI Hash**, leave it at the welcome
screen, and run:

```powershell
./packaging/windows-appcontainer-webview2/inspect-process-tree.ps1 -DurationSeconds 30
```

Run the repository's existing Sysmon/process-creation capture over the same
window. The polling script records live descendants and their tokens, but it
cannot prove that a short-lived or reparented crash-handler process never
existed. Reconcile every process-creation event rooted at the packaged host with
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
