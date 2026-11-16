# macOS Scaleway candidate evidence

This directory indexes the macOS acceptance run performed on 10 November 2026.

## Identity

- Commit: `ef89bc7c6fc4bb0c2f3b441112a3ce3e1decc779`
- Candidate ZIP SHA-256: `ca5d5de55b20f1ebbb3a6f6efcf7d44b127113c788e1906202c032381fd9bb6a`
- Reported executable version: `gami-hash dev`
- Host: Scaleway Apple M2 Pro Mac mini, 16 GB RAM
- OS: macOS Sequoia 15.8.3

The tested executable came from the intended v1.6.1 commit, but its embedded version remained `dev`. The run therefore establishes functional behavior for the commit and artifact hash; it does not establish an exact versioned v1.6.1 macOS release artifact.

## Files

- `ACCEPTANCE-SUMMARY.md`: detailed scope, results, defects, and release decision.
- `results.json`: machine-readable environment, passed scenarios, and limitations.
- `archive-manifest.txt`: contents of the retained full evidence archive.
- `SHA256SUMS.txt`: checksum of the retained full evidence archive.

The full archive is stored outside the source repository at `gami-hash-test/mac-os/scaleway-2026-11-10/macos-acceptance-scaleway-2026-11-10.tar.gz`. Its checksum was recomputed after download and matched `SHA256SUMS.txt`.

## Evidence boundary

The full archive contains the packet capture, filtered filesystem trace, process traces, screenshots, CLI logs, and generated CSV manifests. The 6.7 GB unfiltered filesystem trace was excluded from the portable archive after an app-relevant filtered trace and summary were generated.

The active GUI network observation covered the main process and separately named WebKit helpers. No app-attributed external flow was observed. This is scenario-bound runtime evidence rather than an enforced inability to use the network.
