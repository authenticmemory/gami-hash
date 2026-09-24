# Automatic Windows signing

The `Build signed Windows installer` workflow runs manually or on `test-v*` and
`v*` tag pushes. It uploads signed GitHub Actions artifacts; it does not publish
a GitHub Release. Signing is mandatory: missing configuration or an invalid
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

1. Run tests and the existing Wails/NSIS build. This produces a temporary unsigned
   installer and generates Wails' NSIS support files.
2. Sign and timestamp both `build/bin/gami-hash.exe` (GUI) and
   `build/windows/installer/gami-hash-cli.exe` (CLI).
3. Verify their Authenticode status, timestamp presence, and legal organization.
4. Rerun only NSIS with the signed inputs, replacing the temporary installer.
   Do not rerun Wails: doing so rebuilds the GUI and loses its signature.
5. Sign and timestamp the final installer, then verify all three files.
6. Calculate download checksums on the finished signed files, create the dependency
   inventory, and upload the artifacts.

The installed GUI is named `GAMI Hash.exe`; the installed CLI is `gami-hash.exe`.
Both originate from the signed inputs above. The NSIS-generated uninstaller is
not separately signed by this workflow.

## First run

After merging/pushing the workflow and configuring the environment, run it from
**Actions > Build signed Windows installer > Run workflow** on the allowed branch.
Download `gami-hash-windows`. Check the installer signature, install on a test
machine, and check signatures on both installed executables. Compare the download
against `SHA256SUMS-windows.txt`.

If Azure Login fails, check the exact federated subject, tenant, client ID, and
environment name. If signing returns 403, check the service principal's profile
Signer role and allow time for role propagation. Neither failure should be worked
around by uploading unsigned artifacts.

## References

- [Microsoft signing action](https://github.com/Azure/artifact-signing-action)
- [GitHub OIDC with Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure)
- [Artifact Signing roles](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles)
