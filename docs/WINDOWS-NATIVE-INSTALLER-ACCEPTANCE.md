# Windows native installer acceptance

The production Windows installer is per-user, x64, self-contained, and named
**Authentic Memory Hashing Tool**. `GamiHash.exe` and the `gami-hash` command
remain stable implementation names so upgrades and institutional scripts do
not break.

## Packaging decision

Keep the self-contained installer. The approximately 69 MB download avoids a
.NET runtime prerequisite and any installer-time network dependency. A smaller
framework-dependent installer is unsuitable for offline and managed
institutional deployment. Revisit this only if the supported Windows baseline
guarantees the required .NET Desktop Runtime.

## Acceptance matrix

Run each scenario as the same standard Windows user. Preserve a manifest and
an interrupted run outside the installation directory throughout the matrix.

1. **Fresh install:** select the desktop shortcut and CLI. Confirm the finish
   page can launch the app. Run `verify-installed.ps1 -ExpectedVersion VERSION
   -ExpectDesktopShortcut -ExpectCli` in a new PowerShell.
2. **Upgrade:** start a hash, stop it, leave the app open, and install the next
   version. The installer must close the app gracefully. Confirm the interrupted
   run is offered and completes, and component selections remain selected.
3. **Same-version repair:** delete the Start shortcut and one installed
   executable, rerun the same installer, and confirm both are restored. User
   manifests and resume state must remain unchanged.
4. **Old EXE migration:** install the signed Wails release, then install this
   release. Confirm the old installation directory, shortcuts, and Installed
   Apps entry are removed and only the current entry remains.
5. **MSIX conflict:** install a production-name MSIX identity, then run this
   installer. It must stop before writing files and instruct the user to remove
   the packaged app through Windows Settings. Development spikes with distinct
   names are outside this conflict gate.
6. **Uninstall:** uninstall through Windows Settings. Confirm executables,
   shortcuts, PATH entry, and registry entries are removed. Confirm manifests,
   checkpoints, and source files outside the install directory are unchanged.
7. **Reinstall:** reinstall with different optional component choices and run
   the verifier with matching switches.

The final release gate repeats this matrix on a clean supported Windows VM
using the exact signed installer intended for publication.

## Signed candidate procedure

1. Push one new `test-vX.Y.Z` tag. Do not move or reuse it. The workflow signs
   the WPF executable and Go worker, embeds those exact files in NSIS, signs the
   installer, verifies every signature and timestamp, and records hashes in
   `windows-release-report.json`.
2. Download the installer from that tag's draft GitHub release. Prepare the VM
   bundle with:

   ```powershell
   .\prepare-windows-release-acceptance.ps1 -Installer .\gami-hash-windows-X.Y.Z-x64-installer.exe
   ```

3. Copy `build\windows-release-acceptance.zip` to the clean VM and extract it.
   Run `install-in-vm.ps1` first. It refuses any installer whose SHA-256 differs
   from `artifact-identity.json`.
4. Run the acceptance matrix plus the idle and hashing captures from the same
   extracted directory. Each capture summary embeds the signed installer's
   identity. Archive manifests, screenshots, summaries, Sysmon exports, and
   packet captures under one evidence directory.
5. Compare `artifact-identity.json` with the CI `windows-release-report.json`.
   The installer SHA-256 must match. Create stable tag `vX.Y.Z` on the same
   commit as `test-vX.Y.Z`. CI promotes those exact accepted Windows bytes;
   never replace assets on an existing candidate or stable release.

The UI actions, SMB credentials, cloud placeholder state, cancellation timing,
and clean-machine install lifecycle remain manual because CI cannot faithfully
exercise those external Windows states. Hash checks, signing checks, packaging,
fixture generation, event export, and artifact correlation are automated.

## Cleanup gate

Do not delete the AppContainer and broker experiments until the signed native
candidate's evidence bundle has been archived and reviewed. After that gate,
remove the obsolete prototype workflows and packaging directories in one
reviewable cleanup commit. Keep the historical evidence and decision records.
