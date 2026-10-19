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
