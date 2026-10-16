# Phase 2 Go file-handle probe

This is a disposable AppContainer experiment, not the GAMI Hash engine or a
release artifact. It asks whether a contained Go process can use Windows'
AppContainer-aware `*FromApp` APIs to open a picker-selected directory, read a
file by handle, and create and remove a test file in a separate selected output
folder. It does not write to the selected source.

Build on Windows with Go 1.27 or later:

```powershell
./packaging/appcontainer-phase2/build-go-probe.ps1 -Go 'C:\path\to\go.exe'
```

Bundle the resulting ignored `build/bin/appcontainer-phase2/Phase2GoProbe.exe`
in the disposable MSIX with
`packaging/appcontainer-phase1/build-probe.ps1 -Version 0.1.7.0 -Sign
-Phase2GoPath <absolute exe path>`. The native worker launches it only for the
five-file `local-fixture` in direct `*FromApp` mode, logs its PID and
AppContainer token, and writes its stdout/stderr to package LocalState as
`phase2-go-probe.log`.

Version 0.1.5.0 also tests WinRT brokered handles. The native worker requests
an OS read handle from a picker-selected `StorageFile` and a separate write
handle in the selected output folder, then launches the Go child with inherited
copies. It logs the child in `phase2-inherited-go-probe.log` and removes the
temporary output file. This is a disposable experiment; a product version must
restrict handle inheritance to the intended handles and validate provider
behavior. Microsoft's API references are
[IStorageItemHandleAccess](https://learn.microsoft.com/en-us/windows/win32/api/windowsstoragecom/nn-windowsstoragecom-istorageitemhandleaccess)
and [IStorageFolderHandleAccess](https://learn.microsoft.com/en-us/windows/win32/api/windowsstoragecom/nn-windowsstoragecom-istoragefolderhandleaccess).

Version 0.1.6.0 creates the destination through WinRT first, then obtains its
write handle. This passed the same-VM SMB fixture. Version 0.1.7.0 passed an
on-demand transfer on that fixture: it started the contained Go child,
duplicated both WinRT-granted handles into the running process, and sent their
numeric values over an anonymous pipe. The child read and hashed the 13-byte
source file and wrote one byte to the separate output file. Its log is
`phase2-dynamic-go-probe.log`. This tests one transfer; the product's versioned
multi-request protocol remains open.

Version 0.1.8.0 adds a sequential manifest-stream experiment. The native
worker enumerates the selected source through WinRT, duplicates each read-only
file handle into one running Go child, and sends only that handle value and a
hex-encoded UTF-8 relative name over a pipe. The child writes a five-column
CSV through a separately granted destination handle. The broker log is
`phase2-manifest-go-probe.log`; the CSV is named
`phase2-go-manifest-<pid>-<tick>.csv` in the picked output folder. This is
still a probe: it does not use the product engine's resume path, verify
provider identity, or implement the complete error policy.

Signed 0.1.9.0 adds an acknowledgement after each file and a final completion
acknowledgement. The broker waits before sending the next handle, so at most
one source handle is outstanding in the child. The Go probe also calls the
engine's shared hashing and CSV-field functions. The five-file local and
same-VM SMB runs passed the frozen oracle. The 501-file Google Drive CSV was
byte-identical to the independently checked 0.1.8.0 fresh-file run. These
tests establish the small protocol's functionality on those fixtures; they
do not implement product resume, error, identity, or publication behavior.

Signed 0.1.10.0 exposed a security failure: the WinRT walker followed a
junction outside the selected source and hashed the outside file. Signed
0.1.13.0 showed that `System.FileAttributes` exposes the reparse bit on this
local junction. Signed 0.1.14.0 refused it before the worker completed
enumeration or a manifest. The guarded probe then reproduced the verified
local, same-VM SMB, and Google Drive manifests byte for byte. This is a
narrow fixture result. The current probe
rejects every reparse item, including any cloud item represented that way;
source/output identity and provider tests remain open. See the
[Phase 2 evidence](../../docs/evidence/2026-10-16-windows-appcontainer-phase2/README.md).

Signed 0.1.15.0 tried `StorageFolder::IsEqual` against the source and all
descendant folders before output creation. It returned false for an output
junction into the source and wrote another manifest inside the source.
This candidate identity check failed; do not use this probe on real data.

The probe is a capability check. A product adapter still needs canonical
source/output identity, reparse and provider handling, read-only source
operations, atomic output replacement, persistence, and engine CSV/resume
parity. Do not infer SMB or cloud behavior from the local fixture.
