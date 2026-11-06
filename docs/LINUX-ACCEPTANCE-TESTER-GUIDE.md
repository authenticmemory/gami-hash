# Ubuntu Linux acceptance tester guide

Use this guide on Ubuntu 26.04.1 x64 with the exact Linux GUI and CLI candidate artifacts. Run GAMI Hash from a standard, non-administrator account. Test the GUI and CLI separately.

The completed v1.6.1 result is recorded in [Linux v1.6.1 acceptance](LINUX-ACCEPTANCE.md). This guide remains the procedure for future candidates.

## 1. Record the test environment

Record:

- candidate filenames and expected SHA-256 hashes;
- Ubuntu version and kernel version;
- physical hardware or VM details;
- tester username;
- desktop environment.

## 2. Install monitoring tools and create fixtures

```bash
sudo apt update
sudo apt install tcpdump strace cifs-utils
mkdir -p ~/GamiTest/{source,outputs,evidence,smb}
printf 'alpha\n' > ~/GamiTest/source/alpha.txt
printf 'beta\n' > ~/GamiTest/source/beta.txt
dd if=/dev/zero of=~/GamiTest/source/large.bin bs=1M count=512
```

Keep every result file outside the selected source directory.

## 3. Verify and install the GUI

```bash
cd ~/Downloads
sha256sum -c SHA256SUMS-linux-gui.txt
sudo apt install ./gami-hash-linux-amd64-gui.deb
gami-hash --version
```

Verify the detached OpenPGP signatures with the published GAMI Linux signing key before installation. Record the key fingerprint and verification output.

## 4. Verify and unpack the CLI

```bash
cd ~/Downloads
sha256sum -c gami-hash-linux-amd64.tar.gz.sha256
tar -xzf gami-hash-linux-amd64.tar.gz
chmod 755 gami-hash-linux-amd64
./gami-hash-linux-amd64 --version
```

Verify its detached OpenPGP signature as well.

## 5. Start packet capture

```bash
sudo tcpdump -i any -n -s 0 \
  -w ~/GamiTest/evidence/network.pcap
```

Run this in a separate terminal before launching GAMI Hash. Stop it with `Ctrl+C` after completing all scenarios.

## 6. Run and trace the GUI

Launch the GUI through `strace`:

```bash
strace -ff \
  -e trace=network,file \
  -o ~/GamiTest/evidence/gui-trace \
  gami-hash
```

For each scenario, record the result filename, file count, any error, and a screenshot.

1. **Idle:** Leave the GUI untouched for two minutes.
2. **Local source:** Hash `~/GamiTest/source` and save under `~/GamiTest/outputs`.
3. **Cancel and resume:** Start hashing the source containing `large.bin`, cancel, then resume.
4. **Restart and resume:** Cancel another run, close the GUI, reopen it, and resume.
5. **Changed file:** Cancel, change `alpha.txt`, resume, and confirm the final CSV contains its new SHA-256.
6. **Overwrite rejection:** Create an output containing `DO NOT REPLACE`, record its SHA-256, and select it as the output. The GUI must reject it and preserve its bytes.
7. **Unreadable file:** Create a file and remove its read permission:

   ```bash
   printf 'blocked\n' > ~/GamiTest/source/blocked.txt
   chmod 000 ~/GamiTest/source/blocked.txt
   ```

   Confirm the error log uses a relative path. Restore access afterward:

   ```bash
   chmod 600 ~/GamiTest/source/blocked.txt
   ```

8. **Large file count:** Hash at least 10,000 small files and confirm the CSV row count.
9. **SMB source:** Mount the test share and hash it:

   ```bash
   sudo mount -t cifs //SERVER/SHARE ~/GamiTest/smb \
     -o username=USERNAME,uid="$(id -u)",gid="$(id -g)"
   ```

10. **Mapped location:** Repeat the SMB run through its mounted path and compare the manifest with the direct SMB test fixture.
11. **External-drive root:** Select the root of an expendable external drive. Attempt to save the output on that drive; GAMI Hash must reject it. Save outside the drive and rerun.
12. **Cloud storage:** Test cached and online-only files only when the provider supplies a supported Linux client with those states. Google Drive has no Drive for desktop client on Linux, and Ubuntu 26.04 removed GNOME's Google Drive Files integration; record this as unsupported rather than substituting a third-party client as equivalent evidence.

## 7. Run and trace the CLI

```bash
strace -ff \
  -e trace=network,file \
  -o ~/GamiTest/evidence/cli-trace \
  ~/Downloads/gami-hash-linux-amd64 \
  --root "$HOME/GamiTest/source" \
  --output "$HOME/GamiTest/outputs/cli.csv"
```

Also leave the CLI running during an active large-file test long enough to capture its behavior. Repeat cancellation with `Ctrl+C` and resume using the same output path.

## 8. Review network and write activity

```bash
grep -RniE 'socket|connect|sendto|sendmsg|bind|listen' \
  ~/GamiTest/evidence/*-trace* \
  > ~/GamiTest/evidence/network-syscalls.txt
```

```bash
grep -RniE 'O_WRONLY|O_RDWR|O_CREAT|O_TRUNC|unlink|rename' \
  ~/GamiTest/evidence/*-trace* \
  > ~/GamiTest/evidence/write-syscalls.txt
```

Review the matching lines manually. Local sockets used by the Wails GUI must be distinguished from external network connections. Confirm that no write targets the selected source. Treat SMB and cloud-provider traffic as filesystem-provider activity unless a GAMI-owned process is shown to initiate it.

## 9. Uninstall and verify preservation

```bash
sudo apt remove gami-hash
command -v gami-hash || true
```

Confirm the installed application is gone and manifests under `~/GamiTest/outputs` remain intact.

## 10. Return the evidence

Send:

- checksum and OpenPGP verification output;
- all generated manifests and error logs;
- `network.pcap`;
- every `gui-trace*` and `cli-trace*` file;
- `network-syscalls.txt` and `write-syscalls.txt`;
- screenshots and a pass/fail note for every scenario;
- the recorded environment details.

