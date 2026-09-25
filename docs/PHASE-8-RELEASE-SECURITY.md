# Phase 8 Release Security

Windows signing is implemented using organization-owned Azure Artifact Signing
and GitHub OIDC. Production acceptance remains pending; macOS notarization is
not implemented by the Windows workflow.

## Implemented scaffolding

- `go.mod`, `go.sum`, `frontend/package-lock.json`, and pinned Wails CLI
  version define the current dependency set.
- `.github/workflows/build-macos.yml` builds a clean macOS universal test app
  and publishes a SHA-256 checksum.
- `.github/workflows/build-windows.yml` requires the reusable security checks,
  builds and signs Windows GUI/CLI payloads and the installer, verifies their
  signatures, and stores tag-run checksums/artifacts in a draft release.
- `.github/workflows/build-linux-cli.yml` builds a Linux CLI-only tarball
  without linking Wails, GTK, or WebKitGTK.
- `.github/workflows/security-checks.yml` runs `npm audit` and `govulncheck`.
- `build-windows-installer.ps1` produces a local Wails/NSIS installer.
- The Windows installer exposes optional components for a desktop shortcut and
  command-line PATH access. PATH access is intentionally off by default.
- The Windows installer includes a GUI-subsystem executable for double-click
  use and a separate console-subsystem `gami-hash.exe` for CLI use.
- `release-dependency-inventory.ps1` captures Go modules, npm dependency tree,
  and lockfiles beside release artifacts.
- `wails.json` now contains product metadata for app manifests/installers.

## Still required before production

- Windows independent acceptance on the final signed release candidate; see
  [WINDOWS-ACCEPTANCE.md](WINDOWS-ACCEPTANCE.md).
- macOS Developer ID Application signing, hardened runtime, notarization, and
  stapling.
- Linux GUI package acceptance: packaging workflows exist, but their passing
  status and installation compatibility must be established separately.
- Formal CycloneDX or SPDX software bill of materials for Go and frontend
  dependencies. The current dependency inventory is an interim artifact, not a
  standards-complete SBOM.
- Clean-machine install verification on supported Windows and macOS versions.
- Firewall/runtime verification of the zero-network claim.
- Explicit confirmation that production builds do not enable WebView developer
  tools or remote navigation.

Unsigned Windows installers and ad-hoc signed macOS apps are feedback builds
only. They must not be presented as institution-ready releases.
