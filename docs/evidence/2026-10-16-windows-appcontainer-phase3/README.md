# Windows AppContainer Phase 3 evidence

Date: 2026-10-16  
Environment: disposable Windows 11 x64 VMware guest, standard `gami_runner`
session, development-signed MSIX

## Candidate

- Version: `0.3.5.0`
- Package identity: `AuthenticMemory.GAMIHash.Phase2Product`
- Package file: `gami-hash-phase2-product-0.3.5.0-x64.msix`
- SHA-256: `eeefe631654e540fedd68a41df7dc1840af0936713daef26e1aec8cef0a15995`
- Installed status: `Ok`

The retained package and raw runtime logs are ignored build artifacts. This
directory preserves the reviewable results without treating a development
certificate or MSIX as source.

## Runtime matrix

| Case | Classification and decision | Result |
|---|---|---|
| Local source and destination | Both `Local`; no notice | Fresh worker exit 0, PID 5928 |
| Same-VM SMB source and destination | Both `Network/cloud`; reason `UNC network path`; approved | Fresh worker exit 0, PID 3924 |
| Google Drive source and destination | Both `Network/cloud`; reason `volume supports remote storage`; approved | Fresh worker exit 0, PID 8948 |
| SMB denial | Notice declined | No worker line; destination snapshot unchanged |
| Persisted Google Drive Resume denial | Selections restored, reclassified, notice declined | No worker line; destination snapshot unchanged |
| Retry after SMB denial | Notice appeared again and was approved | Fresh worker exit 0, PID 4400 |
| Source junction escape | Both classified `Local` | Refused: `source contains a reparse point or provider alias` |
| Destination junction resolving inside source | Both classified `Local` | Refused: `selected destination is inside the selected source` |

The local and SMB manifests each contained five rows and were byte-identical,
with SHA-256
`44d3e7b354d57772404877970963f8de2974dfa9d02f5c9a39f7b3980a076232`.
The previously verified Phase 2 fixtures remained intact.

## Denial evidence

The SMB Fresh denial status was:

```text
Source classification: Network/cloud
\\GAMI-HASH-VM\GamiPhase1Loopback\source
Reason: UNC network path
Destination classification: Network/cloud
\\GAMI-HASH-VM\GamiPhase1Loopback\output
Reason: UNC network path
Operation declined; no preflight, hashing, or output creation was started
```

Independent before/after inventories compared destination relative names,
sizes, modification times, and SHA-256 values. They differed only in the
inventory capture timestamp. The persisted Google Drive Resume denial had the
same result. Neither denial produced a product-worker status line.

## Policy tests

`storage_consent_test.exe` covers:

- automatic local/local authorization;
- network/cloud and unknown denial without approval;
- approval for network/cloud and unknown storage;
- source identity substitution;
- destination identity substitution;
- material reclassification;
- destination remap and resume invalidation.

The launcher validates the authorization before process creation. The broker
validates it again before accepting storage requests.

## Cloud completeness finding

An independent source walk found 502 Google Drive entries. The final production
WinRT broker emitted 501 rows with no size or SHA-256 mismatches and omitted
only hidden `desktop.ini`:

```json
{"SourceFiles":502,"ManifestRows":501,"Missing":1,"MissingPaths":["desktop.ini"],"Mismatched":0,"Extra":0}
```

An experimental raw-handle build emitted 502 correct rows, but the same
enumeration route failed with access denied on the local AppContainer fixture.
It was reverted before `0.3.5.0`. Phase 3 consent is therefore passed, while a
broader claim that every filesystem entry is represented remains open.

## Result

**PASS for the tested Phase 3 consent matrix.** The result establishes the
classification, explicit-consent, denial, identity-binding, remap, and resume
contract on this VM. It does not establish perfect remote-provider detection,
release readiness, or hidden/system-file collection completeness.
