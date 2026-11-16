# macOS candidate acceptance

## Scope and verdict

The candidate from commit `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779` was tested on **macOS Sequoia 15.8.3** on a Scaleway Apple M2 Pro Mac mini with 16 GB RAM.

| Candidate asset | SHA-256 |
|---|---|
| `gami-hash-macos-universal.zip` | `ca5d5de55b20f1ebbb3a6f6efcf7d44b127113c788e1906202c032381fd9bb6a` |
| Retained evidence archive | `10a6ad2a5a6ac3594d1c929b387d64454b16cff49eb15ec6d5ea63ae19648ef2` |

Functional acceptance passed for the tested commit. The GUI and CLI covered local hashing, 10,000 files, a 128 GB sparse file, cancellation and resume, restart and resume, changed files, overwrite rejection, unreadable-file reporting, a mounted APFS volume, an SMB mount, and OneDrive.

The application and its separately named WebKit helpers produced no process-attributed external network flow during the active GUI trace. Packet and filesystem captures were retained as supporting evidence. This conclusion applies to the tested workflows and observation windows; it is not an operating-system-enforced network prohibition.

The ZIP is **not accepted as an exact v1.6.1 release artifact** because its executable reports `gami-hash dev`. The version-embedding and verification gate was added after this artifact was built. A correctly versioned, Developer ID signed and notarized package still needs an identity, launch, local-hash, network-smoke, and removal retest.

## Results

| Scenario | Result |
|---|---|
| Signature validation and Apple Silicon launch | Pass; ad hoc test signature |
| Local GUI and CLI hashing | Pass |
| 10,000-file source | Pass |
| 128 GB sparse file, cancel and resume | Pass |
| Process restart and resume | Pass |
| Changed-file rehash | Pass |
| Existing-output protection | Pass |
| Unreadable-file relative-path report | Pass |
| Mounted APFS volume and output containment | Pass with mounted-image scope |
| SMB-mounted folder | Pass |
| OneDrive cached file | Pass |
| OneDrive online-only file | First read timed out during hydration; retry passed |
| Source-write observation | Pass for tested source roots |
| Active GUI network observation | No GAMI or WebKit external flow observed |

## Defects and limitations

- The executable reports `gami-hash dev`; the package identity does not establish v1.6.1.
- The package is ad hoc signed and is not notarized.
- The first read of the online-only OneDrive file timed out while OneDrive hydrated it. A retry recorded both files with independently matching hashes.
- After that timeout, the completion screen reported total scanned bytes as recorded bytes even though the failed file was absent from the CSV.
- The external-volume test used an APFS disk image. It covers mounted-volume selection, containment, hashing, permissions, mounting, and removal, but not physical USB identity or hotplug events.
- `nettop` process sampling can miss a very short connection. The multi-minute active trace, packet capture, and filesystem evidence provide strong observed evidence within that limit.

## Retained evidence

The durable evidence index is in [`docs/evidence/2026-11-10-macos-scaleway-candidate`](evidence/2026-11-10-macos-scaleway-candidate/README.md). It records the environment, artifact identity, result matrix, archive manifest, and checksums.

The full 164,941,712-byte evidence archive is retained outside the source repository at `gami-hash-test/mac-os/scaleway-2026-11-10/macos-acceptance-scaleway-2026-11-10.tar.gz`. Its SHA-256 matches the value above. The archive contains the raw packet capture, filtered GAMI and WebKit filesystem trace, process traces, screenshots, CLI logs, and output manifests. The 6.7 GB unfiltered filesystem trace was deliberately excluded from the portable archive after the filtered trace and machine-readable summary were produced.

## Release gate

For the final macOS package:

1. Build from the intended release commit with the embedded version verification gate enabled.
2. Require the executable and bundle metadata to report the intended version.
3. Verify Developer ID signature, notarization, and Gatekeeper assessment.
4. Run launch, local hashing, short process-attributed network observation, and removal checks on the exact packaged bytes.
5. Retain the artifact checksum and focused retest evidence before describing that package as accepted.
