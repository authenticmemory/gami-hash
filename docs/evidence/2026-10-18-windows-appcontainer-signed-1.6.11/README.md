# Signed Windows AppContainer 1.6.11 acceptance evidence

Date: 2026-10-18

## Exact artifact

- Package: `gami-hash-windows-1.6.11.0-x64.msix`
- Source revision: `7255d7620c4293d26e596b3d95204c6ab0a0cb1a`
- SHA-256: `0f1586634a678630bf5bfb792207183e5b04177bbc05c08141b590c3e49e6c58`
- Signature: organization signed and Microsoft timestamped
- Package family: `AuthenticMemory.GAMIHash.Windows_gvy2j2522dmkc`
- Trust level: `appContainer`
- Declared capabilities: none

The only product change from the previously accepted 1.6.10 candidate is that
the bounded `--appcontainer-network-probe` diagnostic is compiled into the
release executable. It runs only when explicitly activated with that argument.

## Direct-socket negative control

The installed packaged application was activated with the diagnostic argument.
Activation returned success and PID 3056. DNS lookup of `example.com` returned
no host. IPv4 TCP attempts to a private address and `1.1.1.1:443` failed with
Windows access-denied errors. IPv6 private and public attempts reported no
reachable network.

Connectionless UDP `write()` calls returned success at the API boundary. The
simultaneous full-packet PktMon capture contains zero copies of the unique
`GAMI-SPIKE` datagram payload, zero `example.com` query strings, and zero public
IPv4 or IPv6 target-address encodings. This is consistent with WFP dropping the
UDP attempts before packet emission, as observed in the earlier development
control. The capture contains unrelated VM traffic and is retained as
`network-probe.pcapng`.

Result: **PASS for the tested DNS, TCP, and UDP routes.** This establishes an
OS-enforced negative control for those explicit attempts from the exact signed
release process. It is not a mathematical proof covering every Windows network
API or future OS configuration.

## Online-only Google Drive control

`cloud-online-control-20261018.bin` was generated outside the VM and uploaded
through the Google Drive website. Before any content read in the VM, the user
observed Google Drive's cloud/online-only icon. Its expected properties were:

- Size: 1,048,576 bytes
- SHA-256: `4f727b6c549bab926cf30ccf87eb82967a585920060007ddad0577e46ade55ec`

Signed GAMI Hash 1.6.11 hashed the selected Drive folder to a local output. The
six-row manifest contains exactly one control-file row with the expected size
and SHA-256. The manifest SHA-256 is
`b99fba52b9bf7895e50428da34bd1347e6babb584121173f3f79e60675321b2d`.

Result: **PASS for Google Drive first-read hydration.** The pre-read online-only
state is a user-observed provider icon because Google Drive exposes the streamed
file to ordinary Windows metadata APIs as `Normal`. Provider-side network
activity belongs to Google Drive, outside the GAMI process boundary. This test
does not generalize automatically to OneDrive or other providers.

## Files

- `release-report.json`: signing and exact-artifact metadata
- `network-probe-launch.txt`: packaged activation result and PID
- `network-probe.json`: per-route socket API results
- `network-probe.pcapng`: simultaneous all-VM packet capture
- `online-control-manifest.csv`: resulting six-row manifest
- `online-control-verification.json`: independent control-row comparison
