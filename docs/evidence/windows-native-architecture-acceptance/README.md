# Windows native acceptance summary

This directory retains compact machine-readable results from the pre-release native architecture acceptance run. Raw virtual-machine images, packet captures, ETL files, scripts, screenshots, temporary credentials, and obsolete AppContainer evidence were removed after review.

The acceptance build used internal version `0.3.10`; this was not a public product version. The same architecture was rebuilt as signed candidate `test-v1.6.0`, installed, launched, used for a local hash, and verified with `gami-hash --version`. The exact candidate bytes were then published as v1.6.0.

Published v1.6.0 Windows installer SHA-256:

```text
1c6ee47771ae1458f04e7e1d9457038d961398D25D3A6F275C3B816363B97DF6
```

Retained JSON summaries cover local cancellation/resume, changed-file rehashing, cached and online-only OneDrive files, unreadable-file handling, and a 10,000-file manifest. Remote-storage and network conclusions are summarized in `docs/WINDOWS-ACCEPTANCE.md`.
