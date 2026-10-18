# Windows AppContainer productization and storage matrix

Date: 2026-10-18
Candidate: `AuthenticMemory.GAMIHash.Windows_1.6.7.0_x64__49hsk8vwag5ka`

This is engineering evidence for the development-signed candidate. It is not
final release certification. The package uses the disposable certificate
`CN=GAMI Hash WebView2 AppContainer Spike`; it is not organization or Store
signing.

## Verified results

| Scenario | Result | Evidence |
| --- | --- | --- |
| Local, large files | PASS | 8 files, 2.0 GiB; all hashes matched; manifest SHA-256 `640158d9672c4fd3783e8eb677c5d803a57b805879c7cb1bec2c012cbacf4491` |
| UNC SMB | PASS | 5 files; all hashes matched; manifest SHA-256 `2e345b2bd481a1198edc05245ee689398ceae55fc278d2d85c556f587394281b` |
| Mapped drive | PASS | `Z:\` output was byte-identical to the UNC run; classification remained uncertain and required explicit consent |
| Cached Google Drive files | PASS | 5 files; all hashes matched; manifest SHA-256 `9bb31c00cbfd9ba09f1209ed08c7a73a135ebd03749286cab93d5cb1998dba0c` |
| Changed file during interrupted run | PASS | Resumed to 1,024 unique rows and replaced the changed file hash; manifest SHA-256 `5af7439cef4613c4ae8e07267d8b817b2e05f27b58bd5efd27c3609fe50a9c1e` |
| Revoked SMB grant | PASS | Restore stayed open and showed an actionable unavailable-access warning; see `revoked-access.png` |
| Large interrupted manifest | PASS | Restored exactly 1,000,000 rows from a 140,000,063-byte CSV after browser local storage was cleared; see `large-manifest.png` |
| Upgrade while open | PASS | Development package upgrades completed with the app open |
| Normal close | PASS | Host and GAMI-specific WebView2 descendant counts reached zero within five seconds |
| Enumeration feedback | PASS | Live elapsed time updates once per second; the 1,024-file fixture started in about 6 seconds locally and 8 seconds over SMB |
| Genuine online-only cloud placeholder | NOT TESTED | Google Drive kept the attempted fixture cached and would not expose an online-only placeholder through the test setup |

The large-manifest fixture contains synthetic rows and was used only to test
bounded restore and row counting. It was deliberately not resumed as a hash
run.

## Remaining release gates

1. Exercise a genuine online-only placeholder and record hydration or failure behavior.
2. Build the release artifact with the organization or Store signing identity.
3. Repeat the full storage matrix, process containment inspection, and attributed network capture against that exact signed artifact.
