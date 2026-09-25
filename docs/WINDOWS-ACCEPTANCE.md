# Independent Windows release acceptance

Status: pending. Record results against the exact signed installer, not a local
development build. Use a disposable Windows VM and copies of data. No Go, Node,
Wails, or developer tooling should be needed by the installed application.

Record: tester, date, Windows version/architecture, tag, commit, installer SHA-256,
WebView2 version, storage type, and pass/fail evidence for every item below.

1. Download the candidate from its draft release (a maintainer may need to provide
   the files). Compare `Get-FileHash -Algorithm SHA256` to the supplied checksum.
   Verify the installer has a valid Authenticode signature and timestamp from
   Authentic Memory. After installation, verify both `GAMI Hash.exe` and
   `gami-hash.exe` likewise. The generated uninstaller is currently unsigned.
2. Install as a standard user. Confirm no unexpected elevation, working shortcuts,
   GUI startup, and optional CLI PATH access in a new terminal. Check behavior
   with WebView2 present and absent: the latter must give actionable instructions.
3. Check the GUI executable and installer Properties versions match the numeric
   tag version. Confirm `gami-hash --version` preserves the full tag.
4. Hash copied fixtures: empty files, nested directories, spaces, Unicode, long
   paths, and duplicate contents. Independently compare file SHA-256 values with
   `Get-FileHash`. Confirm the manifest has five columns including
   `source_record_id`, whose value equals `relative_path`. Import into GAMI Local.
5. Compare GUI and CLI manifests for the same unchanged source tree. Record file
   counts, hashes, errors, and omissions. Confirm output within the source tree is
   rejected. Check read-only media and symlink/junction skipping.
6. Cancel and resume; forcibly terminate and resume on disposable data; modify,
   remove, and add source files between runs. Confirm no duplicate rows or silent
   reuse of stale entries. Run a multi-hour representative collection test.
7. Save source hashes before and after processing. Confirm contents remain
   unchanged. Test unreadable files and unavailable output storage; errors must
   be visible, and incomplete work must not be presented as complete.
8. Upgrade an existing installation, then uninstall the NEW candidate. Put a
   sentinel text file, a CSV, and a nested directory of unrelated files in the
   chosen installation directory first. They must survive uninstall byte-for-byte.
   Check shortcuts and the application's PATH entry are removed, while unrelated
   PATH entries remain. Also test uninstall from an otherwise empty installation.
   Do not use an old uninstaller for this safety test: old releases recursively
   removed the installation directory.
9. Observe application and child WebView processes with network monitoring while
   idle, hashing, canceling, and resuming. Record destinations and separate OS
   certificate/reputation checks from application traffic. Do not claim verified
   zero-network operation without captured evidence. Check production developer
   tools and remote navigation are unavailable.
10. Document SmartScreen/antivirus behavior and any confusing prompts. Publish the
    draft only after failures are resolved and the release owner signs off. Keep
    prior signed versions and checksums for rollback; check checkpoint/schema
    compatibility before attempting resume with an older version.

Independent user acceptance does not replace an independent code review of source
filesystem safety, resume handling, and release trust boundaries. A formal SBOM
and reproducibility evidence remain tracked in PHASE-8-RELEASE-SECURITY.md.
