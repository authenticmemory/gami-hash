# Phase 5: GUI Boundary

Status: **PASS**

## Boundary

`internal/app.Service` is the only application service the future Wails
adapter may expose. It accepts folder/output dialog requests, resume
inspection, preflight, start, cancel, progress/result events, and opening the
last output folder.

The service accepts user intent, not trusted conclusions. It converts a small
set of run modes into `engine.Options`; arbitrary engine flags are not exposed.
`engine.Validate` performs read-only canonical validation during preflight and
`engine.Run` repeats validation immediately before doing work. A stale,
bypassed, broken, or malicious frontend therefore cannot turn preflight into
authorization.

The engine enforces its own worker ceiling. Progress delivery is bounded and
non-blocking, so a frontend that stops consuming events cannot block hashing or
grow memory without bound. Terminal results displace stale progress rather
than being silently suppressed.

## Authority allocation

| Operation | Frontend authority | Go authority |
|---|---|---|
| Choose source/output | Request native dialog | Return selected path |
| Inspect resume | Supply output path | Validate checkpoint and manifest |
| Preflight | Submit intended run | Canonicalize and enforce safety rules |
| Start/cancel | Request action | Own context, lifecycle, and state |
| Progress/result | Render event | Produce authoritative event |
| Open output folder | Request action | Open only the last engine result |
| Traverse/hash/write | None | Engine only |

## Gate evidence

Boundary tests directly submit malformed and hostile requests, bypass
preflight, stop consuming progress, request unsafe output inside the source,
cancel without a run, and open output without a completed result. The tests
verify that engine safety remains authoritative and the source is unchanged.

The gate is complete when these tests pass and the Wails adapter exposes only
this service rather than the engine or filesystem primitives directly.

`internal/wailsadapter.Backend` is the sole bindable value. An executable
allowlist test freezes its public method set to the seven approved operations.
Lifecycle hooks are package functions rather than exported methods on the
bound value, so they cannot become accidental frontend calls. Native folder
and save dialogs use the Wails Go runtime; progress and terminal results use
the single `gami:engine` event.

For this gate, "malicious frontend" means arbitrary or out-of-order calls to
the exposed bridge. Replacement of the signed frontend bundle is a release
integrity threat handled by signing and packaging controls. Browser network
containment and Content Security Policy remain mandatory Wails-shell controls;
this boundary does not pretend that method allowlisting alone disables a
WebView's own browser APIs.

## Gate result

**PASS:** all source-tree and manifest safety decisions remain enforced by Go
when preflight is bypassed, requests are malformed, calls arrive out of order,
or progress events are not consumed. The TypeScript frontend has no bound
traversal, hashing, checkpoint, manifest-writing, or path-validation method.
