# GAMI Hash macOS acceptance summary

## Scope

- Candidate: GAMI Hash commit `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779`
- Candidate ZIP SHA-256: `ca5d5de55b20f1ebbb3a6f6efcf7d44b127113c788e1906202c032381fd9bb6a`
- Host: Scaleway Mac mini, Apple M2 Pro, 16 GB RAM, 512 GB storage
- OS: macOS Sequoia 15.8.3
- Test date: 10 November 2026

## Conclusion

The tested candidate passed the core macOS hashing workflows on the stated host and OS: local folders, large files, 10,000 files, cancel and resume, process restart and resume, changed files, unreadable files, overwrite protection, a mounted APFS volume, an SMB mount, and OneDrive files after they were locally available.

The distribution is **not ready for an unconditional v1.6.1 acceptance claim**. The installed application identifies itself as `gami-hash dev`, so the artifact does not carry a verifiable v1.6.1 version. Two product limitations were also observed in the OneDrive workflow.

## Results

| Area | Result | Evidence or limitation |
|---|---|---|
| Signature and launch | Pass | Application signature validated and the GUI launched on Apple Silicon. |
| Local GUI hashing | Pass | Three files were recorded with independently matching SHA-256 hashes. |
| Large file, cancel and resume | Pass | A 128 GB sparse fixture was cancelled, resumed and completed with matching hashes. |
| Restart and resume | Pass | The app process was restarted and the resumed output matched independent hashes. |
| Changed file | Pass | The changed file's new SHA-256 was recorded correctly. |
| Existing output protection | Pass | Existing sentinel output remained byte-for-byte unchanged and the app rejected reuse. |
| Unreadable file | Pass | Readable files were recorded; the relative path and permission error were written to the adjacent error log without exposing an absolute path. |
| 10,000 files | Pass | Output contained 10,000 unique file rows plus the header. |
| Mounted volume | Pass with scope limit | An external/removable APFS disk image was hashed and output-inside-source was rejected. This does not prove physical USB detection or hotplug behavior. |
| SMB mounted folder | Pass | Paths and hashes from a real loopback SMB2 mount were correct. This proves mounted-network-share behavior, not a remote-network outage scenario. |
| OneDrive cached file | Pass | Cached file hash matched independently. |
| OneDrive online-only file, first attempt | Partial | GAMI triggered hydration, but the first read timed out and the file was omitted with `FILE_READ_FAILED`. |
| OneDrive retry after hydration | Pass | Both files were recorded with exact independent hashes and no error log. |
| Network behavior | Pass for observed test window | A multi-minute active GUI hash produced no GAMI or WebKit rows in the process network trace. Packet and filesystem traces were also captured. This is strong observed evidence, not proof that no possible execution can ever make a network request. |
| Source integrity | Pass for observed roots | 725,986 GAMI/WebKit filesystem events were filtered; no write-like events targeted the tested source roots. |

## Product defects and limitations

1. **Artifact version is ambiguous.** The installed app reports `gami-hash dev`. Fix version embedding and retest the final packaged v1.6.1 artifact before release acceptance.
2. **Online-only OneDrive files are not reliable on first access.** The first attempt timed out while hydration completed. A retry succeeded. The app should wait for hydration or clearly ask the user to make files available offline before hashing.
3. **The completion screen overstates recorded bytes after an error.** It displayed `1 files (47 B) were recorded` although the CSV contained only the 21-byte cached file; 47 B was the total scanned size. Recorded counts and bytes should describe successful CSV rows.
4. **Physical USB-specific behavior was not tested.** The mounted-volume test covers filesystem selection, output safety, hashing, permissions, mounting and removal, but not hardware identity or hotplug events.
5. **The no-network conclusion is bounded.** The active trace covered the tested workflows and found no app-attributed network flow. Sampling cannot exclude every hypothetical ultra-short flow or behavior outside the tested scenarios.

## Release decision

Treat the functional macOS acceptance as **passed with documented limitations** for commit `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779`. Do not label the current ZIP as a fully accepted v1.6.1 release artifact until its embedded version is corrected and the final packaged artifact receives a short identity, launch and smoke-hash retest.
