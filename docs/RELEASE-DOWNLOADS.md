# Release downloads and website deployment

## Stable release flow

1. Create an immutable `test-vX.Y.Z` Windows candidate.
2. Complete acceptance on that exact signed installer.
3. Create `vX.Y.Z` on the same commit.
4. The `Publish signed downloads` workflow verifies and promotes the Windows candidate, builds the signed Linux CLI and GUI artifacts, creates `gami-hash-downloads.json`, and publishes one GitHub release.
5. The workflow sends `repository_dispatch` with event `tool-release` to `authenticmemory/AuthenticMemory_Website`.

Published releases and tags are immutable. Correct mistakes with a new version.

## Published assets

Stable release names include:

- `gami-hash-windows-amd64-installer.exe`
- `gami-hash-linux-amd64.tar.gz`
- `gami-hash-linux-amd64-gui.tar.gz`
- `gami-hash-linux-amd64-gui.deb`
- `gami-hash-linux-amd64-gui.rpm`
- Checksums, detached Linux signatures, dependency metadata, and `gami-hash-downloads.json`

The website copies only approved public release assets and validates the manifest and Linux signatures. Windows Authenticode is verified on the signing runner and can be checked by users after download.

## Configuration

`WEBSITE_DISPATCH_TOKEN` must have access to dispatch the website repository workflow. Windows and Linux signing environments must allow the trusted release tags.

If the website dispatch or deployment fails after GitHub publication, repair the website workflow or account state and rerun its deployment. Do not recreate or mutate the published tool release.

For v1.6.0, GitHub release publication succeeded. The subsequent website job was prevented from starting because GitHub reported failed account payments or an exceeded spending limit. Resolve that account billing state and rerun the website deployment before treating the website as synchronized.

Local manifest test:

```text
node --test scripts/create-download-manifest.test.mjs
```
