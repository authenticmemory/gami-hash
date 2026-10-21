# Windows v1.6.1 signed acceptance evidence

This directory records acceptance of the exact signed `test-v1.6.1` Windows installer. It remains a test prerelease and has not been promoted to production.

## Artifact identity

- Commit: `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779`
- Installer: `gami-hash-windows-1.6.1-x64-installer.exe`
- Size: `60,923,280` bytes
- SHA-256: `f58fa1270c74f88ae0f8a872997959ec5b6527c602d7ce52f49a807c4bf777ab`
- Signer thumbprint: `78164A8EA4844D648B86AE316343C0917D2C14F6`
- Test account: standard Windows user `gami_runner`, Medium integrity

`candidate-verification.json` records the downloaded installer signature and hash. `installed-payload-verification.json` records valid signatures for the installed GUI, engine, and uninstaller.

## Results

| Scenario | Result |
| --- | --- |
| Fresh per-user install and optional CLI PATH | Pass |
| Local hashing | Pass, 64 files and 512 MiB |
| Cancel and immediate resume | Pass |
| Close, reopen, and resume | Pass |
| Changed file during interruption | Pass; final manifest contains the new hash |
| Existing output replacement | Rejected; original bytes and SHA-256 preserved |
| Unreadable file | Pass; relative path only in the error log |
| 10,000-file manifest | Pass |
| Whole-drive source and output containment | Pass; output inside `R:\` rejected |
| UNC SMB source | Pass |
| Mapped-drive source | Pass; manifest equals UNC result |
| Cached OneDrive files | Pass |
| Online-only OneDrive files | Pass after hydration |
| Idle/local/UNC/mapped/online-only/drive-root captures | Pass at Medium integrity |
| Procmon source-write trace | 189 GAMI source events, zero writes |
| Signed uninstall, manifest preservation, reinstall | Pass |

The `captures` directory contains compact summaries. `functional-manifests` contains the generated test manifests and relative-path error logs. `procmon-gami-source-events.csv` contains the filtered source-drive events.

`raw-evidence.zip` retains the packet ETL/PCAPNG files, Sysmon exports, raw Procmon PML, manifests, and verification JSON. Its SHA-256 is `f16c72d3c4cd192bd5a163e80bdce385dd95568b9e582d796626ab6d5491536a`. The uncompressed Procmon PML exceeds GitHub's per-file limit, so the raw files are retained together in this 49 MB archive. `SHA256SUMS.txt` authenticates the retained files.

## Scope

The captures support the statement that no GAMI-owned process made a network or DNS connection in the tested scenarios. SMB and OneDrive produced packet traffic through Windows filesystem providers. This is runtime evidence, not an operating-system policy that makes networking impossible.
