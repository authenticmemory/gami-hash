# Phase 8 Release Security

Phase 8 is partially scaffolded. Signing and notarization still require
organization-owned credentials.

## Implemented scaffolding

- `go.mod`, `go.sum`, `frontend/package-lock.json`, and pinned Wails CLI
  version define the current dependency set.
- `.github/workflows/build-macos.yml` builds a clean macOS universal test app
  and publishes a SHA-256 checksum.
- `.github/workflows/build-windows.yml` builds a clean Windows NSIS test
  installer and publishes SHA-256 checksums.
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

- Windows Authenticode signing with an organization-owned certificate.
- macOS Developer ID Application signing, hardened runtime, notarization, and
  stapling.
- Linux GUI release artifacts: `.deb` first if partner institutions need GUI
  Linux.
- Formal CycloneDX or SPDX software bill of materials for Go and frontend
  dependencies. The current dependency inventory is an interim artifact, not a
  standards-complete SBOM.
- Clean-machine install verification on supported Windows and macOS versions.
- Firewall/runtime verification of the zero-network claim.
- Explicit confirmation that production builds do not enable WebView developer
  tools or remote navigation.

Unsigned Windows installers and ad-hoc signed macOS apps are feedback builds
only. They must not be presented as institution-ready releases.
