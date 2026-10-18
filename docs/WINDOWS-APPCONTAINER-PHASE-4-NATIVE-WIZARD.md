# Phase 4 native Windows wizard

Status: **implementation built; runtime and usability acceptance open**.

## Native flow

The packaged `GamiHash.exe` implements these native screens:

1. Welcome and saved-run offer.
2. Collection folder selection.
3. Result folder and CSV name selection.
4. Review of both classifications and the consent consequence.
5. Scan/hash progress with file count, byte count, elapsed time, and Cancel.
6. Completed, completed-with-review, canceled, or actionable failure result.

Canceled runs offer **Continue now**. Relaunching with saved folder tokens
offers **Continue saved run**. Both paths reclassify the folders and repeat the
Phase 3 approval gate before resume inspection or storage access.

## State contract

The native host persists only:

- the source FutureAccessList token;
- the destination FutureAccessList token;
- the selected CSV filename;
- one Boolean recording whether a canceled or interrupted run can be resumed.

It does not persist source content, credentials, hashes, or provider secrets.
The brokered engine owns the CSV and checkpoint state.

## Failure behavior

The UI distinguishes access revocation, source aliases, output-inside-source,
and unavailable network or provider failures. It preserves the technical error
after an actionable explanation. A failure is never presented as completion.

## Accessibility and scaling

The host uses standard Windows controls, system fonts, tab stops, default
buttons, `IsDialogMessage` keyboard navigation, and per-monitor DPI awareness.
The runtime acceptance must still verify keyboard-only traversal, 100/150/200%
scaling, screen-reader names, and standard-user launch.

## Browser boundary

The native executable has no embedded HTML, JavaScript bridge, browser local
storage, or WebView2 runtime dependency. Static import inspection is recorded
in the Phase 4 evidence. Runtime process-tree evidence remains required because
static imports alone cannot prove what Windows launches at runtime.
