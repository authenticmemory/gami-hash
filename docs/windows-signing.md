# Automatic Windows signing

The `Build signed Windows installer` workflow runs for manual test builds and `test-v*` tags. It requires Azure Artifact Signing through the protected `windows-signing` GitHub environment.

## Required GitHub environment values

Variables:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

The federated Azure identity must have Artifact Signing Certificate Profile Signer access to account `authenticmemorysigning`, profile `gami-public-signing`, at the North Europe endpoint.

## Build order

1. Run dependency checks and Go tests.
2. Build the native WPF GUI and Go worker.
3. Sign and timestamp `GamiHash.exe` and `GamiHashEngine.exe`.
4. Verify both payload signatures.
5. Package NSIS without rebuilding either payload.
6. Sign and timestamp the final installer.
7. Verify all signatures, timestamp certificates, expected organization, and hashes.
8. Write `windows-release-report.json`, checksums, and dependency inventories.
9. Store test-tag assets in an immutable draft release.

The NSIS-generated uninstaller is not separately signed.

## Promotion

Run acceptance against a fresh `test-vX.Y.Z` candidate. Create `vX.Y.Z` only at the same commit after it passes. The stable publisher validates the candidate report, checksum, signature, timestamp, and commit, then republishes the same installer bytes under the stable filename.

Do not reuse test tags, move stable tags, overwrite published assets, upload unsigned binaries, or rebuild Windows between acceptance and publication.

## Troubleshooting

- Azure Login failure: verify the federated subject, tenant, client ID, tag/environment policy, and audience.
- Signing 403: verify the service principal role on the certificate profile.
- Missing timestamp or invalid Authenticode status: fail the release.
- Candidate tag fetch or report mismatch: fix the workflow and rerun validation; do not bypass the immutable artifact checks.

See [Windows acceptance](WINDOWS-ACCEPTANCE.md) and [release publishing](RELEASE-DOWNLOADS.md).
