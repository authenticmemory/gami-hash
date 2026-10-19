# Windows architecture decision

Date: 2026-10-19
Status: Superseded investigation, final decision recorded

## Decision

The production Windows application uses a native WPF frontend and the existing Go engine as a private stdin/stdout JSON worker. The release is distributed through a self-contained NSIS installer.

The AppContainer, storage broker, WebView2-in-AppContainer, MSIX, and WPF spike implementations were removed after the native application passed functional and release acceptance. They are not supported build paths.

## Reason

The previous Wails/WebView2 Windows application created browser subprocesses and did not meet the desired runtime network behavior. AppContainer prototypes added substantial picker, storage, packaging, and process-boundary complexity and repeatedly failed to provide a dependable general-purpose folder workflow across local, SMB, and cloud-backed storage.

The native WPF frontend uses Windows file pickers directly. The Go worker retains the tested hashing, safety, CSV, error, and resume semantics. Runtime captures showed only the WPF parent and Go worker, with zero GAMI-attributed network or DNS events in the tested scenarios.

For a plain-language account of the alternatives that were tested and rejected, see [How the Windows solution evolved](WINDOWS-SOLUTION-JOURNEY.md).

## Boundaries

- Windows: WPF plus Go worker; no Wails or WebView2.
- Linux and macOS: Wails remains until separately replaced.
- The application does not implement upload, telemetry, or automatic updates.
- Runtime evidence supports a scoped no-observed-connection statement. It is not an OS-enforced network prohibition.
