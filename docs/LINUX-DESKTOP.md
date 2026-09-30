# Linux desktop release

The signed desktop downloads target **Ubuntu 24.04, x64 (Intel/AMD)**.
The separate Linux CLI download remains available for machines without a desktop.

Download `gami-hash-linux-amd64-gui.deb` from the Tools page, open Terminal,
and install it with:

```sh
cd ~/Downloads
sudo apt install ./gami-hash-linux-amd64-gui.deb
```

Open **GAMI Hash** from the applications menu, or run `gami-hash` without
arguments. Adding command-line arguments selects CLI mode.

The GUI tarball is an alternative for users who manage their own installation.
It needs GTK 3, WebKitGTK 4.1 and a runtime compatible with Ubuntu 24.04.
It is not a self-contained, universal Linux binary.

The Fedora RPM also contains a native RPM header signature. Fedora can check it
during installation after importing the public key:

```sh
gpg --import gami-linux-public.asc
sudo rpm --import gami-linux-public.asc
rpm --checksig --verbose gami-hash-0.2.0-1.x86_64.rpm
sudo dnf install ./gami-hash-0.2.0-1.x86_64.rpm
```

The desktop downloads and their checksum list also have detached OpenPGP signatures.
See [Linux signing](LINUX-SIGNING.md) for the release key and verification process.

Stable `vX.Y.Z` tags run Windows, Linux CLI and Linux GUI builds before publishing
the combined download manifest. The GUI job installs the Debian package and
checks that the installed application opens a window under Xvfb. This smoke test
does not replace interactive acceptance testing of folder selection, hashing,
cancellation and resume on a real desktop.

The Fedora RPM is currently a CI artifact while Fedora runtime compatibility is
being tested. It will be added to the public download manifest after that test.
