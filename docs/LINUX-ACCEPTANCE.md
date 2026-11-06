# Linux v1.6.1 acceptance

## Scope and verdict

GAMI Hash v1.6.1 was tested on **Ubuntu 26.04.1 x64** using the exact Linux GUI and CLI candidate assets from commit `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779`.

| Candidate asset | SHA-256 |
| --- | --- |
| `gami-hash-linux-amd64-gui.deb` | `aab17c5a0cb70389cf1c79401a961a818890361bfa67666939319de959cc1546` |
| `gami-hash-linux-amd64.tar.gz` | `4e8ccd4744ab72e52467a2a872a756ca88613144a190b8db3d18baf6c3443f27` |

The candidate passed installation, standard-user execution, GUI and CLI hashing, cancellation and resume, restart and resume, changed-file rehashing, existing-output rejection, unreadable-file handling, a 10,010-file source, SMB and bind-mounted paths, mounted-volume containment, independently attached block-volume testing, uninstall, and manifest preservation.

Process-attributed traces reported zero external IPv4 or IPv6 network calls and zero writes to the selected source. Packet capture was host-wide and included SSH and test-host setup traffic, so the process-attributed trace is the basis for the application network conclusion.

## Limitations

- This establishes runtime behavior on Ubuntu 26.04.1 x64. It is not evidence for every Linux distribution or Ubuntu release.
- Google Drive cached and online-only behavior could not be tested equivalently because Google Drive for desktop is unavailable on Linux and the tested Ubuntu release did not provide the former GNOME Google Drive mount.
- The separately attached block volume tested mounted-filesystem and drive-root behavior. It did not test USB-specific hardware detection or hotplug events, which GAMI Hash does not claim.
- The candidate signatures verified cryptographically with fingerprint `EC85 58C8 64C9 D2A4 1AC4 19B7 FA5C 4B8C 1395 EC9E`. At test time the fingerprint had not yet been published through an independent official channel, so publisher identity authentication remained open.

Stable Linux artifacts are rebuilt from the stable tag. Candidate acceptance therefore does not establish byte-for-byte identity with a future stable Linux build; stable artifacts require their own checksum, signature, installation, and smoke verification.

## Evidence packages

The retained evidence packages have these SHA-256 values:

| Package | SHA-256 |
| --- | --- |
| GUI local run and trace evidence | `2d0bec2766741a170a3abf54ae4f6e11abcd813bdb3ad18956783806e1ebdbc6` |
| GUI resume and 10,010-file evidence | `81922b3e92c91da9d84a2035f36ca01baca486af287f3d9829265b7e6b0e0684` |
| GUI output-safety and unreadable-file evidence | `841efc3b9c107e63b68e9ba23e7ff1db2311787c80bea0ab7e2f887c888cb8ce` |
| Attached-volume evidence | `11cad3d512c989160b8f44113bcca54e91c9c685953efcc98809527c9ba15cb8` |

The complete raw traces and generated manifests are retained in the separate test-evidence workspace because they are too large for the source repository.
