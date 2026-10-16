# Phase 3 storage classification and consent contract

Status: **implemented and passed on the tested Windows 11 VM**. This is an
engineering result for development-signed package `0.3.5.0`, not release
certification.

## Decision model

Each selected source and destination is classified as one of:

- `Local`: Windows exposes a local volume and the path is outside the sync
  roots returned by `StorageProviderSyncRootManager`.
- `Network/cloud`: the path is UNC, Windows reports a remote drive, the path is
  in a registered sync root, or the volume advertises remote-storage support.
- `Cannot determine`: Windows does not expose enough metadata to make either
  conservative classification.

Every classification records its display path, reason, and opened-handle
volume/file identity. `Cannot determine` is never treated as local.

## Enforcement

Local/local selections receive automatic authorization. Any network/cloud or
unknown selection requires explicit user approval. A refusal returns to folder
selection before worker creation, preflight, source reads, or output creation.

Authorization is bound to the source and destination identities and material
classifications. The worker launcher reclassifies and validates both folders
before it creates the worker. The broker session repeats that validation after
launch and before it services storage requests. A changed identity or class
invalidates the decision and fails closed. Fresh and Resume use the same gate;
persisted selections are reclassified and require fresh approval when the
current classes require it.

## Notice timing

The notice cannot promise that no earlier network contact occurred. Browsing
inside the Windows picker and asking Windows or a provider for classification
metadata can contact that provider. The guarantee starts before GAMI preflight,
hashing, and output creation.

## Limits

The classifier is conservative, not complete remote-source detection.
Third-party providers can expose incomplete or misleading metadata. Unknown
metadata therefore requires approval instead of silently becoming local.

Google Drive verification also exposed a separate storage-adapter limitation:
Windows.Storage omitted the hidden `desktop.ini` entry. The production broker
hashed 501 visible entries correctly, while an experimental raw-handle walker
found and hashed all 502 entries but could not open the local AppContainer
fixture. The experiment was reverted. Collection completeness for hidden or
system files remains an open acceptance item outside the Phase 3 consent gate.

## Evidence

The test matrix, package digest, denial snapshots, and regression results are
recorded in [Phase 3 evidence](evidence/2026-10-16-windows-appcontainer-phase3/README.md).
