# WPF visual-parity spike

This spike proved that the existing GAMI Hash workflow can be reproduced
without WebView2 while retaining the Go hashing engine. It does not yet
replace the production Wails entry point.

## Gate

- The shell, welcome screen, interrupted-run card, and selected-folder screen
  remain recognizably equivalent at 980 x 715 and 100% DPI.
- The exact Inter and JetBrains Mono variable fonts are embedded as TTF files.
- The Windows `OpenFolderDialog` opens and returns a local folder.
- A sibling Go worker runs over redirected stdin/stdout, without a listener.
- Native Windows folder and save pickers feed the existing Go preflight.
- Start, progress, cancellation, persisted restart/resume, and completion use
  the real hashing engine.
- No `msedgewebview2.exe` process is launched.

The functional gate passed locally on 2026-10-18, including cancellation at
52 recorded files and successful resume to a 565-file, 4.0 GB manifest.
Visual differences remain and belong to the production parity phase.

Build and publish with:

```powershell
.\spikes\wpf-parity\build-spike.ps1 -Publish
```

Launch the standard or interrupted-run fixture:

```powershell
.\build\bin\wpf-parity-spike\GamiHash.WpfSpike.exe
.\build\bin\wpf-parity-spike\GamiHash.WpfSpike.exe --resume-fixture
```

Pass `--capture <path.png>` to save a deterministic WPF screenshot after the
first render. Reference WebView screenshots and diff thresholds are the next
step after the visual direction is accepted.
