# macOS v1.6.1 acceptance status

The available macOS v1.6.1 rerun is **partial evidence**, not completed acceptance.

It verified the candidate ZIP contents, ad hoc code signature, universal x86_64/arm64 bundle, local hashing, a 10,000-file source, and no writes inside the tested source. Its filtered trace showed no external IPv4 or IPv6 call from the main `gami-hash` process.

The run did not satisfy the complete acceptance guide:

- the tester used an administrator account instead of a standard account;
- the expected candidate hash was not independently supplied to the tester;
- restart/resume, changed-file handling, overwrite rejection, unreadable files, SMB, external-drive root, OneDrive, and command-line mode were not completed;
- no screenshots were captured;
- process filtering excluded separately named WebKit helper processes, so the evidence cannot support a whole-application no-network conclusion.

macOS remains an ad hoc signed test build. It is not notarized and is outside the supported production release tier.
