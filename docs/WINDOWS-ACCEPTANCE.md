# Windows release acceptance

## v1.6.0 status

Version 1.6.0 is published. The Windows installer is signed, timestamped, self-contained, and was smoke-tested after installation. Its SHA-256 is:

```text
1c6ee47771ae1458f04e7e1d9457038d961398d25d3a6f275c3b816363b97df6
```

The same native WPF and Go-worker architecture passed the broader acceptance matrix before promotion. The versioned v1.6.0 candidate then passed installation, GUI launch, local hashing, output opening, and `gami-hash --version` before its exact bytes were published.

## Accepted behavior

| Scenario | Result |
| --- | --- |
| Fresh per-user install and launch | Pass |
| Optional CLI and user PATH | Pass |
| Local hashing | Pass |
| Cancel, close, reopen, and resume | Pass |
| Changed file after interruption is rehashed | Pass |
| Cached OneDrive files | Pass |
| Online-only OneDrive hydration | Pass |
| Unreadable file and error log | Pass |
| 10,000-file manifest | Pass |
| UNC SMB source | Pass |
| Mapped-drive source | Pass |
| Old packaged-app conflict detection | Pass |
| Uninstall and reinstall lifecycle | Pass |
| Open folder selects the result | Pass |

## Network evidence

Idle, local, UNC SMB, and mapped-drive captures reported zero GAMI-attributed network and DNS events. The Windows application process tree contained only `GamiHash.exe` and `GamiHashEngine.exe`.

Those captures used the accepted native architecture build identified internally as `test-v0.3.10`. The exact signed `test-v1.6.0` candidate, whose bytes became the public v1.6.0 installer, passed installation and functional smoke testing. An idle capture against that exact public installer remains to be added; until then, the network evidence is architecture-level rather than exact-release evidence.

This supports the scoped statement that no GAMI-owned process made a network or DNS connection in the tested scenarios. It does not prove an OS-enforced prohibition. Windows SMB and cloud providers can transfer data to implement the filesystem operation requested by the user.

## Release gate for future versions

1. Build and sign a new immutable `test-vX.Y.Z` candidate.
2. Verify its release report, Authenticode signatures, timestamps, and checksums.
3. Test fresh install or upgrade, GUI launch, one local run, cancellation/resume, CLI version, and uninstall behavior on the exact candidate.
4. Repeat remote and cloud scenarios when storage behavior or the engine changes.
5. Create `vX.Y.Z` on the same commit. The publisher must promote the accepted Windows bytes without rebuilding.
6. Verify the public release hash before announcing it.
