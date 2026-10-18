# Windows AppContainer Phase 4 evidence

Status: **native welcome screen observed; runtime and usability matrix remains
open**.

## Candidate

- Version: `0.4.11.0`
- Executable: `GamiHash.exe`
- Package: `gami-hash-windows-native-0.4.11.0-x64.msix`
- SHA-256: `cb0d10e686e81de37b2e6e0ea8bcbe387cdb8f90b84938fa8ee1f247858e94ba`
- Signing: disposable development certificate
- Release artifact: no

## Completed build checks

- Full Go suite: pass.
- Native storage components: compile.
- Native consent policy tests: pass.
- Native wizard: compile and MSIX packaging pass.
- Manifest entry point: `GamiHash.exe`, packaged AppContainer classic app.
- Static PE dependency inspection: no WebView2, WinHTTP, WinINet, Winsock,
  URLMon, or browser dependency. Direct dependencies are Windows core UI,
  common controls, C/C++ runtime, COM, and file-from-AppContainer APIs.

## Required runtime matrix

| Check | State |
|---|---|
| Standard-user install and launch | Pending |
| Welcome, source, result-file, review, progress, result | Restyled welcome and successful local result observed in `native-welcome-0.4.11.0.png` and `native-local-result-0.4.11.0.png`; intermediate screen captures pending |
| Keyboard-only navigation | Pending |
| 100%, 150%, and 200% scaling | Pending |
| Local fresh manifest parity | PASS: five rows in `local-gami-hash-0.4.11.0.csv`; every path, size, and SHA-256 matches the frozen fixture in `local-parity-0.4.11.0.json` |
| SMB consent and successful run | Pending |
| Google Drive consent and successful run | Pending |
| Cancel and Continue now | Pending |
| Close/reopen and saved-run resume | Pending |
| Revoked or unavailable source/destination error | Pending |
| Cloud hydration failure message | Pending |
| Output failure message | Pending |
| Runtime process tree has no WebView2/browser child | Idle PASS: `idle-process-tree-0.4.11.0.json` contains only `GamiHash.exe`; active-run capture pending |
| Archivist or other non-developer walkthrough | Pending |

The Phase 4 gate must remain open until these observations are recorded. A
compiled native window and clean import table are insufficient evidence of
feature parity or usability.
