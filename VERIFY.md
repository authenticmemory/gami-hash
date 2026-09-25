# Verifying a release binary

## Requirements

- The Go toolchain version pinned in `go.mod`.
- Node.js and npm for compiling the embedded TypeScript frontend.
- Native Wails/WebView build dependencies for the target operating system.

A GUI release must be built and tested on its target OS. Plain Go
cross-compilation is not sufficient.

## Windows development build

```powershell
git clone https://github.com/authenticmemory/gami-hash.git
cd gami-hash
.\build-windows.ps1 -Version v1.0.0
```

The result is written to `build/bin/gami-hash.exe` and its SHA-256 digest is
printed after a successful build.

The script runs `npm ci`, builds the embedded frontend, and compiles with the
required Wails `desktop,production` tags. A Wails binary built without those
tags intentionally refuses to start.

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
