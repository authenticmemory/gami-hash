# Phase 7 CLI Preservation

The command-line interface remains a thin wrapper around the same Go engine
used by the Wails GUI boundary.

## Current CLI contract

```text
gami-hash --root FOLDER --output FILE.csv [--workers N] [--fresh] [--rehash-existing] [--quiet]
```

Paths containing spaces must be quoted by the shell:

```powershell
gami-hash --root "D:\Archive Drive\Collection A" --output "C:\Manifests\Collection A.csv"
```

Supported flags:

| Flag | Behavior |
|---|---|
| `--root` | Source folder to scan. Required. |
| `--output` | CSV manifest path. Required and refused inside the source tree. |
| `--workers` | Hash worker count from 1 to 64. |
| `--fresh` | Replace prior output state and start over. |
| `--rehash-existing` | Do not trust reusable rows; hash existing files again. |
| `--quiet` | Suppress progress output while retaining final diagnostics. |
| `--version` | Print the tool version. |

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Completed successfully or completed with warning-only skipped special entries. |
| `1` | Fatal failure before a reliable manifest could be completed. |
| `2` | Completed with file processing errors; review the error log. |
| `130` | Interrupted by Ctrl+C; resume state was preserved. |

## Validation added

- CLI quiet mode still writes a completion summary without progress noise.
- Unsafe output paths and invalid worker counts return stable fatal exit code
  `1` with useful diagnostics.
- Worker overrides produce byte-identical manifests for the same source tree.
- CLI and GUI service boundary produce equivalent manifests for identical
  inputs.
- Manifest hashes are emitted as `sha256:<hash>` through the shared engine.
- Manifest rows contain `relative_path,size_bytes,sha256,mtime_utc,source_record_id`; the
  redundant `filename` column is intentionally omitted.
- The Windows installer exposes a separate console CLI. When run without
  arguments in an interactive terminal, it prompts for the root folder and
  output CSV path. Non-interactive invocation still fails fast instead of
  hanging.

Machine-readable CLI output is intentionally not part of version 1. Adding JSON
would create a second output contract without a confirmed integration consumer.
