# Microsoft Store assessment and MSIX prototype

Assessment date: 2026-09-25. Scope: **GAMI Hash**, including its GUI and hashing
CLI. The separate GAMI proof verifier is not part of this package.

## Decision

Proceed with an MSIX prototype, retaining the signed direct-download installer.
The architecture has no obvious MSIX blocker, but the app is **not yet certified
or demonstrated ready for Store publication**. Native installed-package tests,
WebView2 provisioning and Partner Center identity remain release gates.

The prototype uses the existing application, not a rewrite or a captured NSIS
installation. Windows manages installation, Start menu registration, upgrades
and removal. A separate console executable supplies the execution alias.

## Local validation completed

On 2026-09-25, built version `1.0.0.0` on Windows x64 with Go 1.27.0,
Wails 2.15.0 and Windows SDK MakeAppx 10.0.22621.0:

- Frontend TypeScript/Vite build and dependency audit passed.
- MakeAppx manifest/content validation, packing and unpacking passed.
- Extracted GUI/CLI binaries and manifest matched the staging inputs by SHA-256.
- Extracted console binary displayed help and generated a one-file CSV with the
  expected `sha256:` digest; the original file's bytes were unchanged.
- `go test -count=1 -timeout=5m ./...` passed all six packages.
- New workflow YAML parsed successfully; the hosted workflow has not been run.

Prototype package SHA-256:

```text
726f3c1935a59122a87d7aea04493924d1a65f5c5510174060b47cb72e587c0c
```

Local artifact folder:
`build/bin/msix-prototype/1.0.0.0-20db75dfcbcb4aa78a1b2d8d431eed65/`.
This artifact is unsigned. It was not installed, and GUI activation under MSIX,
execution-alias activation, upgrade/uninstall, WACK and Store certification
remain untested. Extracting/running a payload does not exercise package identity.

## Findings from this repository

| Area | Finding | Consequence / remaining gate |
| --- | --- | --- |
| Privileges | Hashing runs as the current user; no service, driver or elevation is required. | Package as a full-trust desktop app with `runFullTrust`. Explain the capability in certification notes. This is not an AppContainer sandbox. |
| File access | The engine reads user-selected roots and writes the CSV to a user-selected destination. | No `broadFileSystemAccess` capability is proposed. Confirm access to Documents, external drives, UNC paths and denied folders under the installed package. |
| Resume data | `internal/engine/engine.go` places `.part.json` and temporary manifest data beside the selected output. `internal/ui/lastrun.go` keeps the last-run pointer in the user's config directory. | Collection data is outside the package. Validate upgrade/resume and uninstall; the pointer may be redirected or removed by MSIX. Do not promise automatic migration from NSIS. |
| Browser profile | `gui.go` uses Wails' default WebView data path. The pinned go-webview2 implementation resolves it under `%AppData%` using the executable basename. | It does not default to writing beside the executable. Test the actual redirected profile, persistence, and cleanup after package installation. |
| WebView2 | The current NSIS macro invokes the online Evergreen bootstrapper when the runtime is absent. | Existing EXE submission is not ready for the Store's offline-installer rule. The MSIX prototype requires preinstalled Evergreen and uses Wails' `-webview2 error` behavior. |
| EXE signing | GUI, CLI and installer signing are implemented. NSIS uninstaller-signing hooks remain commented out. | An EXE Store submission needs a complete PE-signature audit, including generated uninstaller and any bundled runtime. Existing CI signature checks are insufficient evidence of that. |
| Updates | No app self-updater is used. | Store-managed MSIX updates are preferable to building an updater. The EXE Store route would leave updates to us. |
| CLI | Separate console build already exists. | The prototype uses `gami-hash-prototype.exe`, avoiding the direct install's command name. Decide alias ownership/coexistence before production. |
| Concurrent editions | GUI has a single-instance lock with a fixed UUID; NSIS and MSIX use the same application code. | Test side-by-side behavior. Do not silently remove the direct installation or import its state. |
| Branding / metadata | Existing icon and display name are available. | Generated prototype icon sizes are not a reviewed Store listing. Screenshots, description, support/privacy links and age rating are still needed. |

## WebView2 decision still required

For the prototype, install the Evergreen WebView2 runtime **before** launching
the GUI. The package contains no browser runtime and does not silently download
one. The CLI does not require WebView2.

Do not treat “usually installed on Windows” as a verified dependency strategy.
Before Store release, test a clean Windows image with and without Evergreen,
then choose a supported provisioning strategy. Options to evaluate:

1. Evergreen as a documented prerequisite with the Store's supported dependency
   mechanism confirmed for this submission type. An `.appinstaller` dependency
   used for direct distribution does not by itself establish Store provisioning.
2. A fixed-version runtime bundled in the MSIX, configured through Wails'
   `WebviewBrowserPath`. This increases package size and makes runtime security
   updates our release responsibility. It requires another implementation/test
   pass; the prototype does not pretend to include it.

## Build an unsigned prototype

Requirements: Windows x64, Go matching `go.mod`, Node/npm, Wails v2.15.0, and the
Windows SDK including MakeAppx. Run in the repository root:

```powershell
.\build-msix.ps1
```

The same build is available through **Actions → Build MSIX prototype → Run
workflow** after committing/pushing the workflow. It has no signing credentials
and uploads unsigned test artifacts only; it does not publish a release.

If Go or Wails is not on PATH, pass `-Go C:\path\to\go.exe` and
`-Wails C:\path\to\wails.exe`. `-MakeAppx` can select an explicit SDK tool.

The script builds frontend/GUI/CLI from source, creates required PNG assets from
the existing icon, validates and packs with MakeAppx, unpacks it again, and
compares the embedded binaries and manifest byte-for-byte. It restores
`wails.json` even after a build failure and preserves direct-release binaries.

Outputs are in a new `build/bin/msix-prototype/<version>-<unique-id>/` folder:

- `gami-hash-1.0.0.0-x64.msix` (unsigned).
- `SHA256SUMS.txt` (for the unsigned artifact).
- `build-report.json` (identity, version, signing and installed-test status).
- `package/` and `unpacked-check/` (inspection/debugging).

**This does not install an application, create a certificate, change trust,
enable Developer Mode, reserve a Store name, or submit to Microsoft.** Passing
MakeAppx establishes package structure, not Store certification or runtime behavior.

The default identity is `AuthenticMemory.GAMIHash.Prototype`, with publisher
`CN=GAMI Hash MSIX Prototype`, display name `GAMI Hash Prototype` and command
`gami-hash-prototype.exe`. These are deliberately separate from the eventual
Store identity. The minimum OS declared by this prototype is Windows 10 build
19041; only x64 is currently packaged.

## Installed-package acceptance on a disposable test VM

Use a Windows x64 VM with the SDK signing tools and Evergreen WebView2 installed.
Snapshot it first. A local test certificate is for that VM only; it is not the
Authentic Memory signing identity and must not accompany a public download.

Copy the unsigned MSIX to the VM. Open an administrator PowerShell window there,
adjust the two paths below, and run:

```powershell
$package = 'C:\Test\gami-hash-1.0.0.0-x64.msix'
$signtool = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe'
$certificate = New-SelfSignedCertificate -Type Custom `
  -Subject 'CN=GAMI Hash MSIX Prototype' -FriendlyName 'GAMI MSIX VM test only' `
  -CertStoreLocation 'Cert:\CurrentUser\My' -KeyUsage DigitalSignature `
  -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
Export-Certificate -Cert $certificate -FilePath C:\Test\gami-msix-test.cer
Import-Certificate -FilePath C:\Test\gami-msix-test.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
& $signtool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $package
if ($LASTEXITCODE -ne 0) { throw 'Test signing failed' }
& $signtool verify /pa $package
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
Add-AppxPackage -Path $package
```

Signing changes the MSIX bytes, so regenerate its checksum if sharing the signed
test artifact inside the test environment. The build report describes the
original unsigned build, not the VM's signed copy. Revert the VM snapshot after
testing to remove the test installation and certificate trust.

Record results for every row, with Windows version, package version and screenshots:

| Test | Procedure and required result |
| --- | --- |
| GUI launch | Open **GAMI Hash Prototype** from Start as a standard user. No administrator prompt; GUI and folder/output pickers work. |
| CLI activation | Open a fresh terminal, run `Get-Command gami-hash-prototype.exe`, then `gami-hash-prototype.exe --help`. It must resolve the package alias and return terminal output, not launch the GUI. |
| File integrity | Hash a small known fixture folder; compare CSV digests with `Get-FileHash -Algorithm SHA256`. Rehash original files after the test and confirm their bytes did not change. |
| Paths | Repeat with spaces, Unicode names, a removable drive and an authorized UNC share. Verify denied folders produce useful errors rather than elevation or false success. |
| Pause/resume | Pause a sufficiently large run, close the GUI, reopen and resume. Confirm rows are neither missing nor duplicated. |
| Upgrade | Build `-Version 1.0.1.0` with the same identity/publisher and sign using the same VM test certificate. Pause a run on 1.0.0.0, close it, install the update, then resume. Check completion and user settings. |
| Uninstall | Save original/CSV/checkpoint hashes, then remove only `AuthenticMemory.GAMIHash.Prototype` through Windows Settings. Confirm Start entry and prototype alias are gone; originals, CSVs and external checkpoints remain byte-identical. |
| NSIS coexistence | Install both editions in the VM. Check Start entries, single-instance behavior, CLI lookup and each edition's uninstall without removing the other. |
| Runtime absent | In a separate clean VM without WebView2, launch GUI and CLI. Record GUI behavior; the CLI should work. This test does not pass the GUI release gate until the chosen runtime provisioning strategy works. |
| Certification | Run Windows App Certification Kit against the installed signed test package; retain its report. Investigate every failure before Store submission. |

## Move from prototype to a Store submission

1. Enroll the Authentic Memory organization in Partner Center, reserve the app
   name and obtain the **Package/Identity/Name**, **Package/Identity/Publisher**
   and **Package/Properties/PublisherDisplayName** from product identity. Do not
   substitute the Azure Authenticode subject for the Store publisher identity.
2. Finish WebView2 provisioning and installed-package acceptance above.
3. Build using the real identity, publisher, display name and chosen alias:

   ```powershell
   .\build-msix.ps1 -Version 1.0.0.0 `
     -IdentityName 'VALUE_FROM_PARTNER_CENTER' `
     -Publisher 'CN=VALUE_FROM_PARTNER_CENTER' `
     -PublisherDisplayName 'VALUE_FROM_PARTNER_CENTER' `
     -DisplayName 'GAMI Hash' -Alias 'gami-hash.exe'
   ```

   Match every identity field to Partner Center before submission. The fourth version
   component stays zero for Store submissions.
4. Prepare Store listing copy, real screenshots, privacy/support links, age
   rating and capability justification. Suggested capability explanation:
   “GAMI Hash is a desktop preservation utility. It reads user-selected local
   collections and writes SHA-256 CSV manifests and resume checkpoints to a
   user-selected destination. It requires full-trust Win32 execution for its Go
   hashing engine, native file dialogs and WebView2 desktop interface.”
5. Submit the MSIX for certification. Microsoft signs accepted Store packages;
   local prototype signing is not production publisher verification. Keep the
   existing Azure-signed installer for direct distribution.

## References

- [Microsoft Store MSI/EXE package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)
- [Windows distribution paths and Store-managed MSIX signing/updates](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path)
- [WebView2 runtime distribution](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
- [Packaged desktop application behavior and data](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)
- [Console execution aliases](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap5-appexecutionalias)
