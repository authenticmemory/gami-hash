# macOS acceptance tester guide

Use this guide with the exact macOS candidate ZIP and its expected SHA-256. Run the application from a standard, non-administrator macOS account.

The current macOS build is ad hoc signed and is not notarized. These steps provide functional and runtime evidence, but they do not constitute production signing or Gatekeeper acceptance.

The existing v1.6.1 submission is assessed in [macOS v1.6.1 acceptance status](MACOS-ACCEPTANCE.md). It is incomplete and must not be described as completed acceptance.

## Changes after the first test submission

> **NEW — read this before continuing.** You do not need to reinstall macOS, recreate the standard user, or recreate fixtures that still exist. Stop any old monitoring commands, create a new empty evidence directory, and rerun the tests from section 3 onward.

The first submission exposed four problems that these revised steps correct:

1. **REVISED — code signing:** the previous `./*.app` command inspected unrelated applications in Downloads. The command now targets only the GAMI application bundle.
2. **REVISED — process network capture:** `nettop -L 1` recorded one sample and exited before GAMI was running. The command now records 300 one-second samples.
3. **REVISED — filesystem filtering:** the previous broad filter included unrelated applications and private paths. The new filter selects events whose process is `gami-hash`.
4. **NEW — helper-process coverage:** Wails can start separately named WebKit helpers. Record and review those helpers; tracing only the main `gami-hash` process is insufficient for a whole-application network conclusion.

Create a clean directory for the rerun so old and new evidence cannot be mixed:

```bash
mv ~/GamiTest/evidence ~/GamiTest/evidence-first-attempt 2>/dev/null || true
mkdir -p ~/GamiTest/evidence
```

The original packet capture, `nettop` output, and `codesign.txt` must not be reused. The original filesystem trace may be retained as preliminary startup evidence, but it does not replace the complete rerun.

## 1. Record the test environment

Record:

- candidate filename and expected SHA-256;
- macOS version;
- Mac model and Intel or Apple Silicon architecture;
- tester username;
- whether the test is on physical hardware or a VM.

## 2. Prepare fixtures

```bash
mkdir -p ~/GamiTest/{source,outputs,evidence}
printf 'alpha\n' > ~/GamiTest/source/alpha.txt
printf 'beta\n' > ~/GamiTest/source/beta.txt
dd if=/dev/zero of=~/GamiTest/source/large.bin bs=1m count=512
```

Keep every result file outside the selected source directory.

## 3. Verify and install the candidate

```bash
cd ~/Downloads
shasum -a 256 gami-hash-macos-universal.zip
unzip gami-hash-macos-universal.zip
# REVISED: target only GAMI; do not use ./*.app.
APP="$HOME/Downloads/Authentic Memory Hashing Tool.app"
test -d "$APP" || { echo "GAMI application bundle not found"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 \
  | tee ~/GamiTest/evidence/codesign.txt
"$APP/Contents/MacOS/gami-hash" --version \
  | tee ~/GamiTest/evidence/version.txt
```

Require the ZIP hash to equal the independently supplied expected hash and require `--version` to report the candidate tag. Move the application to `/Applications`.

Because the build is ad hoc signed, macOS may block its first launch. Record the warning. If necessary, Control-click the application, select **Open**, and approve the test build.

## 4. Start monitoring

Open three Terminal windows and start these commands before launching GAMI Hash:

```bash
sudo tcpdump -i any -n -s 0 \
  -w ~/GamiTest/evidence/network.pcap
```

```bash
sudo fs_usage -w -f filesystem \
  > ~/GamiTest/evidence/filesystem.txt
```

```bash
# REVISED: collect 300 one-second samples instead of one sample.
sudo nettop -P -L 300 -s 1 \
  > ~/GamiTest/evidence/network-processes.txt
```

The monitoring tools may run with `sudo`; GAMI Hash itself must run as the standard user. Stop each monitor with `Ctrl+C` after completing the tests.

After launching the application, record the main process and every related WebKit helper. Do not treat a trace filtered only to the `gami-hash` executable as whole-application network evidence:

```bash
ps -axo pid,ppid,comm,args \
  | grep -E 'gami-hash|WebKit|Authentic Memory Hashing Tool' \
  | grep -v grep \
  | tee ~/GamiTest/evidence/gami-processes.txt
```

## 5. Run the acceptance scenarios

For each scenario, record the result filename, file count, any error, and a screenshot.

1. **Idle:** Open GAMI Hash and leave it untouched for two minutes.
2. **Local source:** Hash `~/GamiTest/source` and save under `~/GamiTest/outputs`.
3. **Cancel and resume:** Start hashing the source containing `large.bin`, cancel, then resume.
4. **Restart and resume:** Cancel another run, close GAMI Hash, reopen it, and resume.
5. **Changed file:** Cancel a run, change `alpha.txt`, resume, and confirm the final CSV contains its new SHA-256.
6. **Overwrite rejection:** Create an output containing `DO NOT REPLACE`, record its SHA-256, and select it as the output. GAMI Hash must reject it and preserve its hash and content.
7. **Unreadable file:** Create a file and remove its read permission:

   ```bash
   printf 'blocked\n' > ~/GamiTest/source/blocked.txt
   chmod 000 ~/GamiTest/source/blocked.txt
   ```

   Run GAMI Hash. Confirm the adjacent error log names `blocked.txt` without exposing the absolute source path. Restore access afterward:

   ```bash
   chmod 600 ~/GamiTest/source/blocked.txt
   ```

8. **Large file count:** Hash a fixture containing at least 10,000 small files and confirm the CSV row count.
9. **SMB source:** In Finder, select **Go → Connect to Server**, connect to `smb://SERVER/SHARE`, and hash the mounted source under `/Volumes`.
10. **External-drive root:** Select the root of an expendable external APFS or exFAT drive. Attempt to save the output on the same drive; GAMI Hash must reject it. Save outside the drive and run again.
11. **Cloud storage:** Test cached and online-only OneDrive files separately. Confirm online-only files are hydrated and hashed or reported clearly.
12. **Command-line mode:** Run:

    ```bash
    "/Applications/Authentic Memory Hashing Tool.app/Contents/MacOS/gami-hash" \
      --root "$HOME/GamiTest/source" \
      --output "$HOME/GamiTest/outputs/cli.csv"
    ```

The repository does not currently produce a dedicated CLI-only macOS artifact. This command tests the application executable in command-line mode.

## 6. Review the trace

```bash
# Retain the main process plus separately named WebKit helpers identified in
# gami-processes.txt. Adjust the helper-name alternatives to the recorded names.
grep -E '(gami-hash|WebKit[^[:space:]]*)[.][0-9]+[[:space:]]*$' \
  ~/GamiTest/evidence/filesystem.txt \
  > ~/GamiTest/evidence/gami-filesystem.txt

# NEW: extract GAMI socket and connection operations separately.
grep -E 'socket|connect|sendto|sendmsg|bind|listen|accept' \
  ~/GamiTest/evidence/gami-filesystem.txt \
  > ~/GamiTest/evidence/gami-network-operations.txt
```

Check that:

- the main process and every related WebKit helper made no unexpected external connection;
- the application did not write inside a selected source;
- expected SMB and cloud-provider traffic is identified separately from GAMI-owned traffic.

`tcpdump` proves packet activity but does not by itself attribute every packet to a process. `nettop` supplies supporting process attribution and may miss very short-lived activity. If every related WebKit helper was not identified and reviewed, report the network result as incomplete. State these limits in the result.

## 7. Return the evidence

Send:

- the candidate hash, `version.txt`, and `codesign.txt`;
- all generated manifests and error logs;
- `network.pcap`;
- `network-processes.txt`;
- `gami-processes.txt`;
- `gami-filesystem.txt` and `gami-network-operations.txt`;
- screenshots and a pass/fail note for every scenario;
- the recorded environment details.

