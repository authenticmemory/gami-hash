# How the Windows solution evolved

This document explains, in plain language, the main approaches we tried before arriving at the Windows application used by production version 1.6.0 and accepted test candidate 1.6.1.

## The problem we were solving

GAMI Hash already had a working interface built with Wails. On Windows, Wails displayed the HTML, CSS, and JavaScript interface through Microsoft WebView2.

The hashing code itself did not need the internet. WebView2 still introduced browser processes and Windows service traffic that made a strong, easily verified no-network runtime claim difficult. We wanted to keep the existing workflow while producing a Windows release whose own process tree made no network or DNS connections during the tested operations.

Three statements were kept separate throughout the work:

1. The program contains no upload, telemetry, update, or other network feature.
2. No application-attributed network connection was observed during defined tests.
3. Windows technically prevents the application from using the network.

The released solution supports the first statement by design and the second through runtime evidence. It does not claim the third; the final application is not confined by an operating-system network sandbox.

## Path 1: Keep the original Wails and WebView2 application

This was the starting point. It gave us the design and user flow we wanted, and the Go engine already handled hashing, CSV output, errors, cancellation, and resume.

The problem was WebView2. It is a Chromium-based browser runtime, so one application launch creates several browser-related processes. Even when our own code made no network request, those processes complicated the process tree and the network assurance evidence.

**Result:** The application worked, but this was not a clean Windows architecture for the required network claim.

## Path 2: Block network access administratively

We considered using Windows Firewall or another administrator-managed policy to block the application and WebView2 processes.

This could enforce a no-network rule on a managed computer. It would require administrator access, deployment policy, and continued maintenance of rules for multiple processes. The product had to work as a normal per-user installation without asking an institution to configure the machine.

**Result:** Rejected because administrative network policy was outside the product requirements.

## Path 3: Put the application in an AppContainer

AppContainer is a Windows sandbox. In principle, packaging the application without network capabilities would let Windows deny network access.

The sandbox also restricts normal file-system access. GAMI Hash must let a user choose arbitrary local folders, network shares, mapped drives, and cloud-backed folders. The early AppContainer builds could start, but the Windows folder picker or subsequent path access repeatedly failed with access-denied errors. ProcDump confirmed that the failure happened around the picker and Windows Runtime access rather than in the hashing engine.

**Result:** The security boundary was attractive, but the general folder workflow was not dependable.

## Path 4: Put only WebView2 in an AppContainer

We investigated keeping the normal Go application outside the sandbox while placing only the WebView2 renderer inside it.

WebView2 already uses multiple Chromium processes with boundaries controlled by its runtime. There was no supported, simple way for our host application to place the complete WebView2 process family in our own no-network AppContainer while retaining the Wails bridge, file picker, and existing behavior. Doing this ourselves would have meant owning a complex browser host and inter-process communication design.

**Result:** Rejected as an unsupported and fragile product architecture.

## Path 5: Use a storage broker with the AppContainer application

Windows sandboxed applications normally receive access to user-selected files through brokered Windows storage objects instead of unrestricted file paths. We built prototypes around that model.

This worked for some individual storage cases, but it changed a basic assumption in the Go engine: the engine expects ordinary paths and file handles. A complete solution needed a broker protocol, access-token persistence, separate process responsibilities, packaging rules, cancellation, resume, and error recovery. The picker continued to crash in some packaged configurations, and the design was becoming much larger than the hashing product itself.

**Result:** Technically possible for narrow cases, but too unreliable and complicated for the required local, SMB, mapped-drive, and cloud-backed folder support.

## Path 6: Replace WebView2 with another web renderer

Before abandoning the web interface on Windows, we considered other renderers.

- **Ultralight** could render HTML and CSS, but its commercial licensing was unsuitable.
- **Qt WebEngine** bundles Chromium. It would replace Microsoft WebView2 with another large browser runtime, not remove the browser process and network-assurance problem.
- **Chromium or CEF** would require us to package and maintain a browser engine ourselves, with a larger installer and ongoing security updates.

Changing React to Angular or another JavaScript framework would not help. Those frameworks create the interface; a browser engine is still required to render it.

**Result:** None gave us the existing web design, a small maintenance burden, and a simpler network story at the same time.

## Path 7: Build a native Windows interface

We created a WPF prototype that copied the existing screens and flow. WPF uses Windows desktop controls and does not require a browser runtime.

The first prototype proved that the native Windows folder picker worked. We then recreated the complete flow: choose a source folder, choose a result file, confirm, show progress, cancel, resume, report failures, finish, and open the result folder. Design values and font assets from the web application were reused where practical, and visual discrepancies were corrected through direct comparison.

**Result:** The interface could preserve the product workflow without WebView2.

## Path 8: Decide how WPF should call the Go engine

The new WPF interface still needed the mature Go hashing implementation. Rewriting that engine in C# would have duplicated well-tested behavior and created parity risk.

We considered an in-process bridge between .NET and Go, but that would require a native shared-library boundary, memory ownership rules, callbacks, and more difficult crash handling.

We chose a worker process instead:

- `GamiHash.exe` owns the WPF interface and Windows pickers.
- `GamiHashEngine.exe` owns hashing, CSV creation, safety checks, errors, cancellation, and resume.
- The two processes exchange small JSON messages over standard input and output.

This kept the engine reusable, made the process boundary easy to inspect, and avoided embedding either runtime inside the other.

**Result:** This became the production architecture.

## Path 9: Turn the prototype into a releasable product

The native prototype then had to survive normal installation and real storage scenarios. We added and tested:

- a self-contained, per-user NSIS installer;
- an optional command-line component and user `PATH` entry;
- correct upgrades, uninstall, reinstall, shortcuts, and **Run now** behavior;
- signing and timestamp verification for the GUI, worker, and installer;
- local folders, SMB paths, mapped drives, cached and online-only cloud files;
- cancellation, application restart, resume, changed files, unreadable files, and large manifests;
- idle and active process-tree, DNS, and packet captures;
- immutable promotion, so the public installer is byte-for-byte the signed candidate that was tested.

The obsolete MSIX, AppContainer, storage-broker, WebView2 sandbox, and prototype packaging paths were removed after the native Windows architecture was accepted.

## Current solution

The Windows release now consists of two processes:

```text
GamiHash.exe          Native WPF user interface
    |
    +-- GamiHashEngine.exe --native-ui-worker
                       Existing Go hashing engine
```

This solution was chosen because it meets the practical requirements with the fewest moving parts:

- it preserves the established screens and workflow;
- it uses the normal Windows folder and save pickers;
- it supports ordinary local, network, mapped, and cloud-backed paths;
- it keeps the tested Go hashing behavior;
- it removes WebView2 and its browser process tree from the Windows release;
- it installs without administrator rights or a runtime download;
- its two-process behavior can be tested and explained clearly.

The tradeoff is explicit: this architecture provides a program with no network features and no observed application-attributed connections in the accepted scenarios. It does not use AppContainer or firewall policy to make network access technically impossible.

See [Windows architecture](WINDOWS-ARCHITECTURE.md) for the final technical boundary and [Windows acceptance](WINDOWS-ACCEPTANCE.md) for the evidence supporting the release.
