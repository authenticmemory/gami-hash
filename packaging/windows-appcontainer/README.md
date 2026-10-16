# Windows AppContainer product storage components

This directory contains the production Windows storage boundary. It is not a
continuation of `appcontainer-phase1`, which remains disposable evidence.

The packaged native GUI will own the folder pickers and persist their
`FutureAccessList` tokens. `StorageBrokerSession` receives the resolved source
and destination `StorageFolder` objects, establishes identities and
containment, launches the same signed Go executable with
`--contained-worker`, and serves the bounded protocol in
`internal/storageprotocol`.

Current implementation status:

- The Go worker, framed protocol, opaque source namespace, paged listing,
  brokered read handles, destination work handles, publication calls,
  progress and cancellation contract are product code.
- The native broker identity contract is defined below and must fail closed
  when a provider cannot return a stable identity.
- Existing manifest/checkpoint handles are brokered with stable identity and
  hard-link checks. Product cancellation and restart/resume orchestration are
  integrated and runtime-tested by the production integration host.
- Destination publication uses a verified exclusive handle, repeated stable
  identity checks, deletion by handle, and a fail-if-exists rename. Providers
  with ambiguous link capability fail closed.
- Phase 3 classifies both selected folders as local, network/cloud, or unknown.
  Network/cloud and unknown selections require explicit approval bound to the
  opened folder identities. The launcher and broker reclassify and validate
  that authorization before servicing storage requests.
- The native wizard is Phase 4; no WebView bridge should call this component.

Do not package a broker that substitutes a display path or picker token for a
stable storage identity. That would pass ordinary fixtures while remaining
vulnerable to aliases, remaps and path replacement.
