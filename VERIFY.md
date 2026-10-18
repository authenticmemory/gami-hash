# Verifying a release binary

## Requirements

- The Go toolchain version pinned in `go.mod`.
- .NET 8 SDK and NSIS for the native Windows frontend and installer.
- Node.js, npm, and Wails dependencies for Linux and macOS GUI builds.

A GUI release must be built and tested on its target OS. Plain Go
cross-compilation is not sufficient.

## Windows development build

```powershell
git clone https://github.com/authenticmemory/gami-hash.git
cd gami-hash
.\build-windows-installer.ps1 -Version v1.0.0
```

The native WPF GUI and Go worker are written under
`build/windows-native/payload`; the self-contained installer is written under
`build/bin`. SHA-256 digests are printed after a successful build.

The Windows build does not compile or package Wails or WebView2. Linux and
macOS retain their existing Wails build paths.

`-trimpath`, an empty Go build ID, and disabled VCS stamping remove common
sources of build-path variation. This is preparation for reproducibility, not
proof that reproducible signed releases exist.

## Release status

Windows CI builds and tests the frontend and Go code, requires dependency checks,
signs the GUI/CLI and final installer, and verifies signatures and timestamps.
Tag runs store the signed artifacts in a draft GitHub Release for review.
See [Windows signing](docs/windows-signing.md) for configuration.

Windows product metadata uses the numeric release version (for example,
`test-v1.2.3` becomes `1.2.3`); the engine retains the full version string.

A successful workflow does not establish clean-machine behavior or source safety
under all storage failures. Complete [Windows acceptance](docs/WINDOWS-ACCEPTANCE.md)
on the exact signed candidate before publishing its draft release.
The generated uninstaller is not separately signed. User files and WebView data
are preserved during uninstall. Reproducible unsigned builds, a formal SBOM,
independent code review, and runtime network verification remain separate work.
macOS/Linux artifacts are not covered by Windows acceptance. Do not use the
legacy `build.sh` for Wails GUI releases.
