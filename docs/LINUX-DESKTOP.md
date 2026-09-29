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

Both desktop downloads and their checksum list have detached OpenPGP signatures.
See [Linux signing](LINUX-SIGNING.md) for the release key and verification process.

Stable `vX.Y.Z` tags run Windows, Linux CLI and Linux GUI builds before publishing
the combined download manifest. The GUI job installs the Debian package and
checks that the installed application opens a window under Xvfb. This smoke test
does not replace interactive acceptance testing of folder selection, hashing,
cancellation and resume on a real desktop.

The existing Fedora RPM remains a CI artifact only until its runtime compatibility
has been tested on Fedora. It is not included in the public download manifest.
