# Signed Windows AppContainer 1.6.10 acceptance evidence

Date: 2026-10-18

## Exact artifact

- Package: `gami-hash-windows-1.6.10.0-x64.msix`
- Source revision: `1ed178f7003aa407cc1d3ea239b3ecbeef31a8c6`
- SHA-256: `4b9b9e10e11b682b18e5814106edb86456995d399bf5706121c4525753911f84`
- Signer: Authentic Memory gemeinnützige UG (haftungsbeschränkt)
- Signature and Microsoft timestamp: valid
- Package family: `AuthenticMemory.GAMIHash.Windows_gvy2j2522dmkc`
- Manifest trust level: `appContainer`
- Declared capabilities: none

The development package used a different publisher and package family. Windows
could not upgrade it in place. Its package state was backed up, the development
registration was removed, and the organization-signed package was installed.
Picker grants do not migrate between those identities.

## Results

| Scenario | Result | Runtime evidence | Manifest verification |
| --- | --- | --- | --- |
| Process containment | PASS | `GamiHash.exe` and all six observed WebView2 descendants, including the network service, reported `TokenIsAppContainer = true` | `process-tree.json` |
| Idle, 32 seconds | PASS for observed window | 128 VM packets overall; zero GAMI-attributed Sysmon network or DNS events | Not applicable |
| Local hash, 91 seconds | PASS | 232 VM packets overall; zero GAMI-attributed Sysmon network or DNS events | 1,024 rows/files, 1,024 unique paths, zero mismatches; SHA-256 `5af7439cef4613c4ae8e07267d8b817b2e05f27b58bd5efd27c3609fe50a9c1e` |
| UNC SMB hash, 92 seconds | PASS | Zero GAMI-attributed Sysmon network or DNS events; Windows broker/SMB activity is outside the GAMI process attribution | 5 rows/files, zero mismatches; SHA-256 `2e345b2bd481a1198edc05245ee689398ceae55fc278d2d85c556f587394281b` |
| Cached Google Drive hash, 93 seconds | PASS | Zero GAMI-attributed Sysmon network or DNS events; provider activity is outside the GAMI process attribution | 5 rows/files, zero mismatches; SHA-256 `9bb31c00cbfd9ba09f1209ed08c7a73a135ebd03749286cab93d5cb1998dba0c` |

PktMon reported no lost events. The `.pcapng` files contain all VM traffic in
each window; Sysmon files provide process attribution. This supports the narrow
claim that no network or DNS event was observed from the signed GAMI process
tree in these scenarios. It does not claim that Windows SMB or a cloud provider
performed no network activity.

## Open gates

1. **Exact-artifact direct-socket negative control: NOT TESTED.** The release
   build deliberately excludes the diagnostic `appcontainer_network_probe`
   build tag. The development artifact previously passed this control, but that
   result is not substituted for exact-release evidence. A same-token external
   harness is required if this gate remains mandatory.
2. **Online-only cloud placeholder: NOT TESTED.** Google Drive kept the available
   fixture cached. This run establishes cached-provider behavior only.

Until those gates are closed, do not state that every possible network attempt
is categorically prohibited or that online-only placeholders are supported.
