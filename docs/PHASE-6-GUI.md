# Phase 6: Polished Wails Interface

Status: **IN USER ACCEPTANCE TESTING**

## Implemented workflow

```text
Welcome -> Select collection -> Select output -> Review -> Progress -> Results
```

The production frontend is embedded in the executable. It uses the established
GAMI mark, local CSS, system fonts, and no remote scripts, images, fonts, or
analytics. A restrictive Content Security Policy denies network connections.

The interface exposes plain-language trust information, canonical-path review,
native selection dialogs, file/byte progress, estimated time, safe
cancellation, persisted resume discovery, and distinct success, warning,
canceled, and fatal states.

## Early-feedback changes

- Default manifest names include local date and time:
  `gami-hash-YYYY-MM-DD_HH-mm-ss.csv`.
- The progress indicator uses the native HTML `progress` value rather than an
  inline width. The previous inline style was correctly blocked by CSP, which
  made the visual bar appear full despite accurate percentage text.
- Cancellation changes the screen immediately to "Saving checkpoint" and
  explains that active reads and artifact publication must finish safely.
- Traversal checks cancellation while processing directory entries.
- A checkpoint belonging to a different source now opens an explicit conflict
  screen. The user may resume its recorded collection, deliberately replace
  the partial run, or choose a different output.
- The canceled screen shows both the partial CSV and adjacent `.part.json`
  checkpoint locations and explains resume validation.

## Resume storage

On graceful cancellation, the partial CSV is published at the selected output
path and its checkpoint is stored at `<output>.part.json`. On abrupt process
termination, the checkpoint may temporarily reference a hidden
`.gami-manifest-*` working file in the same output directory. The frontend's
local storage remembers only the last selected root/output pair; it contains no
hashes and is never trusted as resume evidence. The Go engine validates the
checkpoint and manifest before reuse.

## Gate

The technical implementation is ready for usability testing. The phase gate
remains open until non-technical test users complete a new run, cancel it, and
resume it without assistance.
