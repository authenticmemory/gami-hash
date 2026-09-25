# Linux packaging

Linux GUI packages are built in GitHub Actions on Ubuntu 24.04.

## Artifacts

The `Build Linux GUI` workflow uploads:

- `gami-hash-linux-amd64-gui.tar.gz`
- `gami-hash_<version>_amd64.deb`
- `gami-hash-<version>-1.x86_64.rpm`
- `SHA256SUMS-linux-gui.txt`

## Debian / Ubuntu

The `.deb` installs `/usr/bin/gami-hash`, a desktop launcher, and the GAMI
icon. It declares:

```text
libgtk-3-0
libwebkit2gtk-4.1-0
```

Install:

```bash
sudo apt install ./gami-hash_<version>_amd64.deb
```

## Fedora

The current `.rpm` targets Fedora-style WebKitGTK 4.1 package names. It
declares:

```text
gtk3
webkit2gtk4.1
```

Install:

```bash
sudo dnf install ./gami-hash-<version>-1.x86_64.rpm
```

## Not yet covered

RHEL, AlmaLinux, Rocky Linux, and older Debian/Ubuntu versions may require
WebKitGTK 4.0 package names and a separate Wails build tag. Do not advertise
the Fedora RPM as RHEL-compatible until that package has been tested.

## Download signatures

See [LINUX-SIGNING.md](LINUX-SIGNING.md) for OpenPGP CI setup and verification.
Detached signatures must be checked before installation; they do not configure APT or DNF trust.
