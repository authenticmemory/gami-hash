# Windows native installer acceptance

The production Windows installer is per-user, x64, self-contained, and named **Authentic Memory Hashing Tool**. Stable executable names are `GamiHash.exe`, `GamiHashEngine.exe`, and optional `gami-hash.exe`.

## Installer requirements

- Correct product name, publisher, numeric version, 64-bit registry placement, and uninstall entry.
- Optional desktop shortcut and CLI PATH component.
- Graceful replacement of running application processes during upgrade or repair.
- Preservation of manifests and resume state stored outside the installation directory.
- Removal of legacy EXE installations and clear blocking of conflicting packaged releases.
- Working fresh install, upgrade, repair, uninstall, and reinstall paths.
- No installer-time network or .NET runtime dependency.

The approximately 65 MB v1.6.0 production installer and 61 MB `test-v1.6.1` candidate are intentionally self-contained.

## Immutable release procedure

1. Push a new, never reused `test-vX.Y.Z` tag.
2. CI builds WPF and Go, signs both payloads, packages NSIS, signs the installer, verifies timestamps, and records `windows-release-report.json` plus checksums.
3. Test the downloaded candidate. Record its SHA-256.
4. Create `vX.Y.Z` at the same commit only after acceptance.
5. The stable workflow downloads and validates the candidate, then publishes the same bytes under the stable download name.
6. Never replace assets or move a published tag.

## v1.6.0

The accepted candidate and stable tag point to commit `751b3dc34617a80bfdc813eb6887a5affb8edab0`. The published installer is byte-for-byte the tested candidate and has SHA-256 `1c6ee47771ae1458f04e7e1d9457038d961398d25d3a6f275c3b816363b97df6`.

## test-v1.6.1

The signed candidate points to commit `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779` and has SHA-256 `f58fa1270c74f88ae0f8a872997959ec5b6527c602d7ce52f49a807c4bf777ab`.

It adds drive-root containment, non-overwriting output publication, timestamped automatic filenames, relative-path error logging, registry-based last-run state, .NET 10, exact embedded versioning, and a separately signed uninstaller. Fresh install, CLI PATH, uninstall, manifest preservation, reinstall, and the complete standard-user storage and capture matrix passed. It remains a test prerelease pending a separate production decision.
