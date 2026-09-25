# Windows acceptance test: step-by-step guide

Status: pending. This guide is for someone who did not build GAMI Hash. You do
not need Go, Node.js, or developer tools. PowerShell is included with Windows.

## Before you begin

Ask the release owner to provide:

- The exact installer being tested, normally
  `Authentic Memory Hashing Tool-amd64-installer.exe`.
- `SHA256SUMS-windows.txt` from the same build, and the release tag and commit ID.
- Access to GAMI Local for the import test, or a teammate who can perform it.
- A disposable Windows test computer or virtual machine and a standard user
  account. Use copies of documents, never an institution's only copy.

If the files arrive in a ZIP, right-click it and select **Extract All**. Keep the
installer and checksum file together. Draft GitHub releases may only be visible
to repository collaborators; the release owner can supply the files directly.

Create a results document. For each numbered section record **PASS**, **FAIL**, or
**NOT TESTED**, with notes and screenshots. A skipped test is not a pass. Record
Windows version (press Windows+R, type `winver`, press Enter), release tag, commit,
date, your name, and whether storage is local, USB, or a network share.

## 1. Check that the downloaded installer matches the release

A checksum is a fingerprint of a file's bytes. This check detects a corrupted or
changed download. It does not itself establish who published the file; obtain the
checksum from the release owner or official release alongside the installer.

1. Open Start, type **PowerShell**, and open **Windows PowerShell**. Do not choose
   **Run as administrator**.
2. Copy the following block. Replace ONLY the example folder in the first line
   with the folder containing your extracted download. Keep the quotation marks.

```powershell
$download = "C:\Users\YOUR-NAME\Downloads\gami-hash-windows"
$installer = Join-Path $download "Authentic Memory Hashing Tool-amd64-installer.exe"
$checksums = Join-Path $download "SHA256SUMS-windows.txt"
Test-Path -LiteralPath $installer
Test-Path -LiteralPath $checksums
```

Both results must be `True`. If not, locate the files in File Explorer and correct
the folder or filename before continuing. If GitHub's ZIP contains subfolders,
use the folder actually containing these two files.

3. In the SAME PowerShell window, paste:

```powershell
$actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$filename = Split-Path -Leaf $installer
$entries = @(Get-Content -LiteralPath $checksums | Where-Object {
  $_ -match ('^[0-9a-fA-F]{64}\s+\*?' + [regex]::Escape($filename) + '$')
})
if ($entries.Count -ne 1) { throw "Expected exactly one checksum entry for the installer" }
$expected = ($entries[0] -split '\s+', 2)[0]
"Expected: $expected"
"Actual:   $actual"
if ($actual -ieq $expected) { "PASS: checksum matches" } else { throw "FAIL: checksum mismatch. Do not run this installer." }
```

**Pass:** `PASS: checksum matches`. Copy the actual hash into your results.
**Fail:** a mismatch or missing entry. Stop and send the output to the release owner.

## 2. Check the signature and timestamp

Keep using the same PowerShell window so `$installer` still refers to your file.

```powershell
$sig = Get-AuthenticodeSignature -LiteralPath $installer
$sig | Format-List Status,StatusMessage
$sig.SignerCertificate | Format-List Subject,NotBefore,NotAfter
$sig.TimeStamperCertificate | Format-List Subject,NotBefore,NotAfter
```

**Pass requires all three:**

- `Status : Valid`.
- The signer Subject contains `Authentic Memory gemeinn?tzige UG (haftungsbeschr?nkt)`.
  The rest of the Subject contains address/certificate information; that is normal.
- The timestamp section is present and identifies a Microsoft timestamp authority.
  An empty section means no timestamp certificate was returned: report it.

Save the output. A short-lived signing certificate is normal for this service;
check the overall `Valid` result rather than rejecting a timestamped signature
solely because its signing certificate has expired.

You can also right-click the installer in File Explorer, select **Properties ?
Digital Signatures**, select the signer and click **Details**. Record whether
Windows says the digital signature is OK. Do not proceed with a non-Valid result
or an unexpected publisher until the release owner investigates.

## 3. Install and open the application

1. Double-click the verified installer.
2. If SmartScreen says **Windows protected your PC / unrecognized app**, take a
   screenshot, click **More info**, and record the publisher. This is a reputation
   warning and is a separate finding from the signature check. Continue with
   **Run anyway** only for this authorized test after steps 1?2 pass and your IT
   policy permits it. Do not disable Defender. If a named threat is reported or
   the file is quarantined, stop and contact the release owner.
3. Record any administrator-password or permission prompt. The default per-user
   installer should not require administrator access.
4. Accept the default installation folder. Record it. On the components screen,
   select the desktop shortcut and **Add GAMI Hash to PATH** for this test.
5. Finish installation, then open the desktop shortcut. Confirm the window loads
   and folder selection works. Screenshot any error or blank window.
6. Open a NEW PowerShell window and run `gami-hash --version`. Expect the complete
   release tag, for example `gami-hash test-v0.1.4`. If the command is not found,
   sign out/in and retry; record if that was necessary. Do not alter PATH manually.

In the original PowerShell window, set the installation path. Change this if you
selected a custom folder:

```powershell
$installDir = Join-Path $env:LOCALAPPDATA "Programs\Authentic Memory Hashing Tool"
$gui = Join-Path $installDir "GAMI Hash.exe"
$cli = Join-Path $installDir "gami-hash.exe"
foreach ($file in @($gui, $cli)) {
  "FILE: $file"
  $s = Get-AuthenticodeSignature -LiteralPath $file
  $s | Format-List Status,StatusMessage
  $s.SignerCertificate | Format-List Subject
  $s.TimeStamperCertificate | Format-List Subject
}
(Get-Item -LiteralPath $gui).VersionInfo | Format-List FileVersion,ProductVersion
(Get-Item -LiteralPath $installer).VersionInfo | Format-List FileVersion,ProductVersion
& $cli --version
```

Both installed executables must meet the signature requirements in section 2.
The GUI and installer numeric versions should match the tag without `test-v` or
`v`: `test-v0.1.4` becomes `0.1.4` (a trailing `.0` is acceptable).
The separate `uninstall.exe` is currently unsigned; record this known limitation.

## 4. Create safe sample files and run the GUI

Paste this into the original PowerShell window. It creates a NEW uniquely named
test folder in your temporary directory, so it does not overwrite existing data.

```powershell
$testRoot = Join-Path $env:TEMP ("GamiAcceptance-" + [guid]::NewGuid().ToString('N'))
$source = Join-Path $testRoot "source"
$output = Join-Path $testRoot "results"
New-Item -ItemType Directory -Path $source,$output,(Join-Path $source 'nested folder') | Out-Null
Set-Content -LiteralPath (Join-Path $source 'hello.txt') -Value 'Hello archive'
Copy-Item -LiteralPath (Join-Path $source 'hello.txt') -Destination (Join-Path $source 'duplicate.txt')
New-Item -ItemType File -Path (Join-Path $source 'empty.txt') | Out-Null
Set-Content -LiteralPath (Join-Path $source 'nested folder\Gr??e.txt') -Value 'Unicode filename'
function Get-SourceSnapshot {
  Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
    [pscustomobject]@{
      Path = $_.FullName.Substring($source.Length + 1)
      Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
  } | Sort-Object Path
}
$before = @(Get-SourceSnapshot)
$before | Export-Csv -LiteralPath (Join-Path $output 'source-before.csv') -NoTypeInformation
"Source folder: $source"
"Save GUI manifest to: $(Join-Path $output 'gui.csv')"
```

In GAMI Hash, select the displayed source folder and save to the displayed
`gui.csv` path. Start hashing and wait for completion.

**Pass:** four files processed, no file errors, and a CSV in the results folder.
Do not edit/resave the CSV in Excel before checking it.

```powershell
$rows = @(Import-Csv -LiteralPath (Join-Path $output 'gui.csv'))
$rows | Format-Table relative_path,size_bytes,sha256,source_record_id
$columns = $rows[0].PSObject.Properties.Name -join ','
"Columns: $columns"
if ($columns -ne 'relative_path,size_bytes,sha256,mtime_utc,source_record_id') { throw 'Unexpected columns' }
if ($rows.Count -ne 4) { throw 'Expected four manifest rows' }
foreach ($row in $rows) {
  $file = Join-Path $source $row.relative_path
  $hash = 'sha256:' + (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($row.sha256 -ne $hash) { throw "Hash mismatch: $file" }
  if ($row.source_record_id -cne $row.relative_path) { throw "Record ID mismatch: $file" }
}
$after = @(Get-SourceSnapshot)
$changes = @(Compare-Object $before $after -Property Path,Hash)
if ($changes.Count) { $changes; throw 'Source files changed' }
'PASS: all four hashes and record IDs match; source contents unchanged'
```

This direct path comparison is for these simple fixtures only. Special encoded
manifest paths require decoding before mapping them to files.

## 5. Compare CLI results and reject unsafe output

```powershell
& $cli --root $source --output (Join-Path $output 'cli.csv') --quiet
"CLI exit code: $LASTEXITCODE"
$guiRows = Import-Csv -LiteralPath (Join-Path $output 'gui.csv')
$cliRows = Import-Csv -LiteralPath (Join-Path $output 'cli.csv')
Compare-Object $guiRows $cliRows -Property relative_path,size_bytes,sha256,mtime_utc,source_record_id
```

**Pass:** exit code `0` and no lines from `Compare-Object`.

Then try an output inside the source folder:

```powershell
& $cli --root $source --output (Join-Path $source 'must-not-create.csv') --quiet
"CLI exit code: $LASTEXITCODE"
Test-Path -LiteralPath (Join-Path $source 'must-not-create.csv')
```

**Pass:** a clear rejection, exit code `1`, and `False` for file existence.

Send `gui.csv` to the teammate running GAMI Local, or upload it through their
provided preflight screen. **Pass:** four accepted rows and no missing
`source_record_id` error. Record the GAMI Local version and preflight result.

## 6. Cancel, resume, and test a larger copied collection

Ask the release owner for a disposable collection large enough to run for several
minutes. Keep the output outside it. Use a fresh output filename for each scenario.

1. Start a GUI run, click Cancel while hashing, then resume with the same folder
   and output. Expect an interrupted/resumable state, then successful completion.
2. Start another run. Open Task Manager (Ctrl+Shift+Esc), select GAMI Hash and
   **End task**. Reopen and resume using the same source and output. Do this only
   with disposable copies.
3. Repeat interruption. While the app is stopped, edit one copied file so its
   content and size change, delete another, and add a new file. Resume. The final
   manifest must reflect these changes, with no deleted entry or duplicate paths.
4. Produce a separate uninterrupted manifest of the final source using a new
   output filename. Compare it with the resumed manifest using the `Compare-Object`
   command in section 5, substituting these two filenames. Expect no differences.
5. Run a representative multi-hour collection. Record duration, file count,
   errors, responsiveness, and storage type. Repeat the before/after source-hash
   comparison from section 4, with `$source` pointing to the copied collection.
   Hashing it independently may take substantial time.

For duplicate detection, run `Import-Csv "YOUR-MANIFEST.csv" | Group-Object
relative_path | Where-Object Count -gt 1` on one line. Expect no output.

## 7. Upgrade and uninstall without deleting user files

Use the disposable machine. Ask the release owner for an earlier installer and
install it first, then install the NEW candidate over it. Confirm the new version
opens and both installed executables still have valid signatures.

Do not run an old uninstaller for this test: old builds recursively deleted the
installation directory. Check the new version is installed before proceeding.
Close the application. In the original PowerShell window run:

```powershell
$sentinelDir = Join-Path $installDir ("AcceptanceKeep-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sentinelDir,(Join-Path $sentinelDir 'nested') | Out-Null
Set-Content -LiteralPath (Join-Path $sentinelDir 'keep.txt') -Value 'Must survive uninstall'
Copy-Item -LiteralPath (Join-Path $output 'gui.csv') -Destination (Join-Path $sentinelDir 'keep.csv')
Set-Content -LiteralPath (Join-Path $sentinelDir 'nested\keep.txt') -Value 'Nested sentinel'
$sentinels = @(Get-ChildItem -LiteralPath $sentinelDir -Recurse -File | Get-FileHash)
$userPathBefore = [Environment]::GetEnvironmentVariable('Path','User')
```

Open **Settings ? Apps ? Installed apps**, find Authentic Memory Hashing Tool,
and select Uninstall (Windows versions may call the list **Apps & features**).
Then run:

```powershell
foreach ($entry in $sentinels) {
  if (-not (Test-Path -LiteralPath $entry.Path)) { throw "Deleted unrelated file: $($entry.Path)" }
  if ((Get-FileHash -LiteralPath $entry.Path).Hash -ne $entry.Hash) { throw "Changed unrelated file: $($entry.Path)" }
}
'PASS: unrelated files preserved'
Test-Path -LiteralPath $gui
Test-Path -LiteralPath $cli
"User PATH before: $userPathBefore"
"User PATH after:  $([Environment]::GetEnvironmentVariable('Path','User'))"
```

Both executable checks must return `False`; sentinel files must remain. The
installation folder should remain because it contains your sentinel files.
Confirm the desktop/Start menu shortcuts are removed. Compare the PATH lists:
only the GAMI installation entry should be removed, not unrelated entries.
Also install/uninstall in a fresh custom folder with no user files; that empty
installation folder should be removed. Record both outcomes.

## 8. Tests requiring the release owner or an IT tester

Do not mark these passed based on the basic tests above. Ask an IT tester to run
these on a disposable machine and provide the stated evidence:

| Scenario | Action | Expected evidence |
| --- | --- | --- |
| WebView2 missing | Use a separate VM without the runtime; do not remove it from a work computer | Clear startup/install instructions; no unexplained blank screen |
| Long paths | Supply a fixture with full paths exceeding 260 characters | Successful manifest and independently matching hashes, or a documented support limitation |
| Read-only storage | Hash copies from read-only media | Correct manifest outside the source; unchanged source contents |
| Junctions/symlinks | Create links in a test tree pointing outside it | Linked content is not followed; omissions are reported |
| Unreadable file | Deny the test user read access to one copied file | Visible error and CLI exit code `2`, not silent full success |
| Output failure | Make a disposable output location unavailable during a run | Visible failure; incomplete work not presented as complete |
| Network activity | Capture application and child WebView traffic while idle, hashing, canceling, resuming | Saved capture with process IDs/destinations; distinguish OS signature/reputation checks from app traffic |
| Production WebView | Attempt developer-tool shortcuts and inspect navigation restrictions | Developer tools unavailable and external navigation blocked; record method used |

Running successfully offline alone does NOT prove the app makes no network
attempts. Network verification requires captured observations and IT analysis.

## 9. Return results; do not declare production readiness yourself

Send the release owner your results, screenshots, PowerShell output, checksums,
and any error logs next to the manifests. Use this format for each failure:

```text
Release tag / installer SHA-256:
Windows version:
Test section:
Steps taken:
Expected result:
Actual result:
Screenshot or log filename:
```

Do not send private collection contents. Keep the original test artifacts so a
failure can be reproduced. The release owner resolves failures, records untested
items, and decides whether to publish the draft. Prior signed releases and
checksums should remain available for rollback; older versions may not accept
newer checkpoints/manifests.

Independent user testing does not replace independent code review. A formal SBOM,
reproducibility evidence, and other open release work are tracked in
[PHASE-8-RELEASE-SECURITY.md](PHASE-8-RELEASE-SECURITY.md).
