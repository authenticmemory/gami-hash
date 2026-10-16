# Windows GUI offline assurance plan

Status: approved direction; implementation and feasibility tests pending. No
release currently passes these gates. The signed v1.5.0
GUI failed the no-network acceptance test; see
[the runtime evidence](evidence/2026-10-16-windows-v1.5.0/README.md).

The phased build sequence and stop/go gates are in the
[Windows AppContainer implementation plan](WINDOWS-APPCONTAINER-IMPLEMENTATION-PLAN.md).

## Product claim to earn

For a specified signed Windows release, on supported Windows versions, the GUI
and every process it launches have no general network capability, initiate no
independent internet connections, and never request write, delete, or
metadata-change access to source entries. Output CSV, checkpoint, logs, and
temporary files stay outside the selected source tree. Files may be selected
from local disks, organization network shares, or supported cloud-backed
folders. Reading network-backed or cloud-placeholder files may cause Windows,
the file-system client, or a cloud sync provider to transfer data. That
storage traffic must be disclosed and measured separately.

The claim applies to the identified release artifact and its process tree.
Windows, antivirus, storage drivers, and other applications are outside that
process tree. Reading can update filesystem access metadata or trigger other
system behavior. A test of one version cannot certify future builds.

The [product contract](V1-PRODUCT-CONTRACT.md#12-zero-network-policy) permits
UNC and mounted network storage. Therefore the product claim is **no
independent app internet communication**, with a stated storage-traffic
exception. It is not "using the app causes zero network packets." Users must
not have to pre-download files simply to make the GUI usable. Path spelling
alone cannot identify all network-backed storage: a mapped drive or cloud
placeholder can look local.

"Any source" means a folder that Windows can expose through a supported file
picker and filesystem provider, and that the user is authorized to read. It
does not automatically include arbitrary web URLs, proprietary repositories,
or providers requiring a separate API integration. Every supported source
class must be demonstrated with a real provider before it is advertised.

## Source and destination selection and consent

1. Let the user select the source folder and CSV destination without a generic
   network notice. After selection, classify **both** locations using metadata
   where possible, before enumerating the source or creating output: direct UNC
   paths, mapped remote drives, registered cloud sync roots, placeholder
   metadata, and known filesystem-provider information. Display `Local`,
   `Network/cloud`, or `Cannot determine` for each. Do not treat a drive letter
   or a cached cloud file as proof of local-only storage.
2. If either selected location is detected as network/cloud, show one specific
   notice and require approval before hashing or writing output. Name the
   affected source or destination and the likely action: Windows or the provider
   may **download source bytes** to read them, **send source reads** over an
   organization network, or **upload/sync the CSV and checkpoint** written to
   a cloud-backed destination. Declining returns to location selection; it does
   not start the run. If both locations are confirmed local, proceed normally
   without a network notice.
3. If either location cannot be classified confidently, do not silently label
   it local. Show a distinct `Cannot determine whether this location uses a
   network` message and require the user to choose another location or approve
   the uncertainty before starting. This is not a claim that the location is
   known to be remote.
4. Record the approved locations and classifications in the run state. Recheck
   on resume because a drive can be remapped or a provider can change. If a
   later check reveals network backing that was not disclosed, stop before
   further reads or writes and ask again.
5. Explain accurately that any storage transfer is performed by **Windows or
   the selected storage provider** to service file reads or writes. GAMI Hash
   has no independent internet connection. Consent cannot reveal every
   provider endpoint or stop pre-existing provider background sync.

The requested notice appears **after** location detection and **before**
hashing. This timing cannot guarantee consent before *all* network traffic:
the Windows picker or filesystem provider may contact a remote location while
the user browses or while metadata is inspected. The interface and assurance
statement must not claim otherwise. This is an informed-consent workflow, not
a perfect detector of all remote storage. A categorical "no network activity
whatsoever for every path labeled local" claim is unavailable for arbitrary
third-party filesystem providers.

## Architecture

1. Keep the existing hashing engine and CSV format. Replace the Windows
   Wails/WebView2 interface with a native Windows interface. Do not include a
   browser runtime, remote assets, telemetry, updater, or crash uploader.
2. Package the GUI as an actual **AppContainer**, with no `internetClient`,
   `privateNetworkClientServer`, or other network capability and no
   `runFullTrust` component. An ordinary MSIX or WinUI desktop package is often
   full trust; packaging by itself does not impose this network restriction.
3. Use Windows file pickers to grant the user-selected source and output
   locations, including network shares and cloud-backed folders where supported.
   Do not add general network capabilities just to open arbitrary UNC paths in
   code. Store program state in app-private storage. Keep output validation in
   the engine. Prove that the existing Go engine can enumerate and read every
   file in a picked folder, retain access across resume, and write the selected
   output under AppContainer. Microsoft documents picker access to network
   shares, but that is not proof that this app's folder workflow will work.
4. For an **OS-enforced inability to change source entries**, prove that the
   source is exposed to the hashing process with read-only rights, for example
   through a constrained read-only handle design or read-only storage. A normal
   picker grant and the engine's current read-only opens alone do not prove
   that the process could never request a write. Any helper that can read source
   data must have its own network and write authority included in the claim.
5. Supply a signed, self-contained offline installer. Installation, signing
   validation, OS updates, and application runtime are separate scopes; test
   installer behavior without a preinstalled browser runtime. Do not silently
   substitute an online bootstrapper or updater.

Microsoft documents that an AppContainer without network capability cannot
access the network, and that its child processes run in the container. It also
documents that desktop apps must explicitly select AppContainer trust level;
`internetClient` omission does not constrain a full-trust desktop app.

## Gates before promising this to an institution

### 1. Feasibility prototype

- Build a minimal native GUI package with actual AppContainer trust level and
  no full-trust helper or network capabilities. Inspect the signed package
  manifest and the token of each running process.
- Select local, mapped-share, UNC-share, and cloud-backed folders through the
  picker. Enumerate and hash a large tree in each case; cancel, close, reopen,
  resume, and write CSV and checkpoint outside the source. Confirm that access
  to children of the selected folder works without direct UNC lookup or
  network capabilities. A picked individual file is not enough for this gate.
- Test NTFS, removable media, long/Unicode paths, denied files, reparse points,
  mapped drives, UNC paths, cloud placeholders, authenticated shares, and
  offline/disconnected storage. Distinguish an ordinary cached cloud file from
  a placeholder that triggers hydration. If arbitrary picked folders require
  a full-trust broker or broad network capability, redesign before promising
  the categorical network claim; that broker would be part of the product's
  network and source-write trust boundary.
- Test source **and destination** classification and consent timing with real
  SMB, OneDrive/SharePoint sync, and at least one other supported provider.
  Verify declining consent prevents hashing and output creation, and that
  cancel/resume cannot bypass it. Record which process owns each
  storage-provider connection, including picker-time activity.
- The current Windows engine rejects every visible reparse point to avoid
  following links outside the source. Microsoft's Cloud Files API uses reparse
  points for placeholders but normally hides them from ordinary apps. Test
  hydrated and online-only files on real sync clients. If placeholders appear
  as reparse points in this process, distinguish cloud placeholders from
  name-surrogate links by tag and preserve the anti-escape rule. Never change
  the blanket skip without that proof.

### 2. Source protection

- Audit every source-tree open by the GUI and all descendants with Process
  Monitor. Fail on write-capable opens, writes, rename, delete, permission, or
  timestamp-change requests.
- Test the normal folder as read-only storage and with deliberately denied write
  ACLs; hashing must still work. Compare source file contents before and after
  idle, hashing, cancellation, and resume.
- To claim **cannot modify**, demonstrate a process-level rights boundary and
  a negative control that deliberately attempts a source write and is denied.
  If only code discipline and runtime observation are achieved, state the
  narrower claim: "the tested release did not modify source files."

### 3. Network protection

- Attempt TCP, UDP, DNS, loopback, and local-network connections from a test
  binary running with the same package identity and token; the OS must deny
  each one. A denied attempt is distinct from a successful connection.
- Capture installation, first launch, idle, hashing, cancellation, resume, and
  exit on a clean VM with process creation, network-flow, DNS, and packet
  telemetry. Attribute descendants and short-lived processes. Fail if any
  app-tree process establishes an independent outbound connection. For network
  shares and cloud placeholders, identify and record the storage-provider or
  system traffic separately; do not mistake its existence for app telemetry,
  or hide it from the institutional report.
- Repeat on each supported Windows version and for every release artifact.
  Publish the artifact hash, signature identity, manifest, test environment,
  raw logs, analysis script, and pass/fail result. Keep sensitive raw logs
  private and publish a redacted report.

### 4. Release control

- Sign the exact package tested and distribute its checksum. Reject release if
  the package includes WebView2, a full-trust helper, network capabilities, or
  online installer steps.
- Run the network and source protection gates in release CI and independently
  on a clean VM. Treat a failed or missing gate as a failed assurance claim.
- Give institutions one bounded written statement naming the build, supported
  storage and Windows versions, excluded OS behavior, and evidence location.
  Reissue it for each release rather than treating one VM run as a permanent
  certificate.

## Decision point

Management requires hashing files where they already reside, including
organization shares and cloud-backed folders. Prototype picker-granted
whole-folder access in a networkless AppContainer before building the rest of
the native GUI. If that prototype fails, an architecture with a storage broker
may be necessary, but its authority and network flows must be included in the
assurance claim. Do not solve the failure by quietly adding broad network
capabilities to the GUI.

## Platform references

- [AppContainer security and network capability](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [MSIX AppContainer configuration and child processes](https://learn.microsoft.com/en-us/windows/msix/msix-container)
- [Desktop package trust levels and capabilities](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations)
- [Windows file access and pickers](https://learn.microsoft.com/en-us/windows/apps/develop/files/file-access-permissions)
- [Cloud Files placeholders and reparse compatibility](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine)
- [Cloud placeholder state from file metadata](https://learn.microsoft.com/en-us/windows/win32/api/cfapi/nf-cfapi-cfgetplaceholderstatefromattributetag)

Microsoft's capability guidance says the file picker can open files on a
network share without requesting `enterpriseAuthentication`, and that a folder
picker can grant access to cloud-synced locations. Its separate guidance for
programmatically retrieving UNC paths lists network capabilities. This
difference is why the whole-folder picker prototype is a release gate.
