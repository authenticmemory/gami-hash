# Signed Windows native release acceptance: 0.3.10

Candidate `test-v0.3.10`, commit
`579cedd65dbc6878fb454ad14fe66660f6f604f8`, installer SHA-256
`13b0675850e2bd6545418cb94c80c619d5be380c64a38467a7b6251a95b99415`.
GitHub Actions signed and timestamped the WPF executable, Go worker, and final
NSIS installer, then verified all three before creating the draft release.

## Results

| Scenario | Result | Evidence |
| --- | --- | --- |
| Fresh install, optional CLI, PATH | Pass | Signed installed payloads; `gami-hash --version` returned `test-v0.3.10` |
| Local source, cancel, close, restart, resume | Pass | `local-resume.json` |
| Cached OneDrive source, local output | Pass | `onedrive-cached.json` |
| Online-only OneDrive hydration, local output | Pass | `onedrive-online-only.json` |
| File changed after cancellation | Pass | `changed-file-resume.json`; final row matches the changed source hash |
| Unreadable file | Pass | `unreadable-file.json`; one good row plus a separate error log |
| 10,000-file manifest | Pass | `large-manifest.json` |
| Idle process/network capture | Pass | `vm/evidence-idle`; zero attributed network and DNS events |
| UNC SMB source, local output | Pass | `vm/evidence-unc-smb`; exact five-row oracle match, zero attributed network and DNS events |
| Mapped-drive source, local output | Pass | `vm/evidence-mapped-drive`; exact five-row oracle match, zero attributed network and DNS events |
| Previous MSIX conflict | Pass | Installer stopped before writing and required removal of the packaged release |

`vm-manifest-verification.json` records the independent comparison of both SMB
manifests with the fixture oracle. Every VM summary embeds the exact candidate
identity. Packet captures contain ordinary host traffic; the Sysmon exports are
the process attribution record. The observed result supports the scoped claim
that no GAMI-owned process made a network or DNS connection in these scenarios.
Windows SMB and cloud providers may still transfer bytes to service filesystem
access.

The disposable SMB account, encrypted share, firewall rule, credential, and
drive mapping were removed after evidence collection.
