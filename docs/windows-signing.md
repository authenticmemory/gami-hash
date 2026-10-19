# Automatic Windows signing

The `Build signed Windows installer` workflow runs manually or on `test-v*` tags.
Stable `vX.Y.Z` tags promote the already accepted, immutable Windows artifact
from the matching `test-vX.Y.Z` draft release. The stable tag and test tag must
point to the same commit. The stable workflow verifies the recorded SHA-256,
Authenticode signature, timestamp, and commit before publishing, then waits for
the Linux builds and triggers Netlify. See
[release deployment](RELEASE-DOWNLOADS.md). Windows test tags create draft releases.
Published releases are never overwritten by reruns. Signing is mandatory: missing configuration or an invalid
signature fails the job before upload.

## One-time Azure and GitHub setup

1. In Microsoft Entra ID, create a single-tenant app registration named
   `gami-hash-github-signing`. Record its Application (client) ID and Directory
   (tenant) ID. No client secret is needed.
2. In its **Certificates & secrets > Federated credentials**, add a credential
   for **GitHub Actions deploying Azure resources**:
   - Organization: `authenticmemory`
   - Repository: `gami-hash`
   - Entity type: **Environment**
   - Environment: `windows-signing`
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject: `repo:authenticmemory/gami-hash:environment:windows-signing`
   - Audience: `api://AzureADTokenExchange`
3. On the existing `gami-public-signing` certificate profile in the
   `authenticmemorysigning` account, assign **Artifact Signing Certificate Profile
   Signer** to the new application's service principal. Scope the assignment to
   that profile. The developer's existing signing permission does not grant the
   workflow access. Do not grant the workflow subscription Contributor or Owner.
4. In GitHub repository **Settings > Environments**, create `windows-signing`.
   Configure selected deployment branches/tags: permit the trusted release branch
   for manual runs and the `test-v*` and `v*` tag patterns. Protect those tags with
   repository rules so only authorized maintainers can create them. Azure's
   environment-based federation trusts this environment, so these restrictions
   determine which source revisions can obtain signing access. Optional required
   reviewers add a release approval gate if the repository plan supports it.
5. Add these **environment variables** (not credentials or client secrets):

   | Variable | Value |
   | --- | --- |
   | `AZURE_CLIENT_ID` | Application ID from step 1 |
   | `AZURE_TENANT_ID` | Directory ID from step 1 |
   | `AZURE_SUBSCRIPTION_ID` | Subscription containing the signing account |

The workflow uses the existing North Europe endpoint
`https://neu.codesigning.azure.net`, account `authenticmemorysigning`, and profile
`gami-public-signing`. It authenticates with short-lived OIDC credentials through
Azure Login. It does not use the developer's Azure CLI session or local
`metadata.json`.

## Build and verification order

1. Pass the reusable dependency security workflow, run Go tests, and build the
   native WPF/Go-worker NSIS installer.
2. Sign and timestamp `build/windows-native/payload/GamiHash.exe` and
   `build/windows-native/payload/GamiHashEngine.exe`.
3. Verify their Authenticode status, timestamp presence, and legal organization.
4. Rerun only NSIS with the signed inputs, replacing the temporary installer.
   Do not rebuild either payload after signing.
5. Sign and timestamp the final installer, then verify all three files.
6. Calculate download checksums on the finished signed files, create the dependency
   inventory, and upload the artifacts.

The installed GUI is `GamiHash.exe`; its private worker is
`GamiHashEngine.exe`. Both originate from the signed inputs above. The
NSIS-generated uninstaller is
not separately signed by this workflow.

## First run

After merging/pushing the workflow and configuring the environment, run it from
**Actions > Build signed Windows installer > Run workflow** on the allowed branch and enter a version such as `test-v0.1.4`.
Alternatively push a new matching tag; that starts the workflow automatically.
Download `gami-hash-windows`. Check the installer signature, install on a test
machine, and check signatures on both installed executables. Compare the download
against `SHA256SUMS-windows.txt`.

Run acceptance against this test-tag artifact. When it passes, create
`vX.Y.Z` at the exact commit referenced by `test-vX.Y.Z`. The stable workflow
promotes the accepted Windows bytes; it does not rebuild or re-sign them. This
is required because timestamped signing is intentionally nondeterministic.

If Azure Login fails, check the exact federated subject, tenant, client ID, and
environment name. If signing returns 403, check the service principal's profile
Signer role and allow time for role propagation. Neither failure should be worked
around by uploading unsigned artifacts.

## References

- [Microsoft signing action](https://github.com/Azure/artifact-signing-action)
- [GitHub OIDC with Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure)
- [Artifact Signing roles](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles)

## Release acceptance and retention

CI artifacts expire after 14 days; test-tag draft release assets are the durable
candidate archive. Complete [Windows acceptance](WINDOWS-ACCEPTANCE.md) on the test
build before pushing a stable version tag. The stable release workflow publishes
both signed platforms automatically. Review its generated release notes before
announcing the release. Keep earlier installers and checksums for rollback.
Do not move a published tag. A rollback uses an earlier signed installer and must
preserve user manifests; manifest/checkpoint version compatibility still applies.
