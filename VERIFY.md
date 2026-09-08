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

## Current limitation

The older multi-platform `build.sh` predates the Wails GUI and must not be used
for a GUI release until the release-engineering phase replaces it with native
platform jobs. Reproducibility, signing, notarization, package generation, and
double-build comparison remain release-gate work.
