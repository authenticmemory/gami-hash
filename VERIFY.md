# Verifying GAMI Hash

## Source verification

```powershell
go test ./...
node --test scripts/create-download-manifest.test.mjs
dotnet build .\windows\GamiHash.Windows\GamiHash.Windows.csproj -c Release
```

Build the Windows installer with:

```powershell
.\build-windows-installer.ps1 -Version v1.6.0
```

It writes the native WPF GUI and Go worker under `build/windows-native/payload` and the NSIS installer under `build/bin`.

## Published v1.6.0

Verify the downloaded Windows installer with:

```powershell
$file = '.\gami-hash-windows-amd64-installer.exe'
Get-AuthenticodeSignature $file | Format-List Status,SignerCertificate,TimeStamperCertificate
Get-FileHash $file -Algorithm SHA256
```

Require `Status: Valid`. The v1.6.0 Windows installer hash is `1C6EE47771AE1458F04E7E1D9457038D961398D25D3A6F275C3B816363B97DF6`.

CI verifies the WPF executable, Go worker, and installer signatures and timestamps before creating the candidate. A stable tag must point to the same commit as its accepted `test-vX.Y.Z` tag and promotes those exact bytes.

## Scope of assurance

The engine contains no upload or telemetry feature. Runtime acceptance observed zero GAMI-attributed network or DNS events during tested idle, local, UNC SMB, and mapped-drive scenarios. SMB and cloud providers can still use the network to satisfy filesystem reads. This evidence is an observation of documented scenarios, not an OS-enforced prohibition on all possible network access.

See [Windows acceptance](docs/WINDOWS-ACCEPTANCE.md) for tested behavior and limits.
