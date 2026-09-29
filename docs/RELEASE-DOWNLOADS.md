# Publish signed downloads and update the website

Push a new stable tag `vX.Y.Z` after acceptance testing. The `Publish signed
downloads` workflow calls both Windows and Linux CLI workflows at that commit.
Both signing environments must allow the tag, and both builds must pass.

The publisher verifies payload checksums, creates `gami-hash-downloads.json`,
attaches both platforms and their dependency inventories, publishes the release,
then sends `repository_dispatch` (`tool-release`) to the website repository.
Set `WEBSITE_DISPATCH_TOKEN` in this repository's Actions secrets to a fine-grained
GitHub token with Contents: Read and write on `authenticmemory/AuthenticMemory_Website`.
Never overwrite a published release.
Draft uploads can be retried before publication.

Test tags continue to run individual builds; Windows test runs retain draft
releases. Manual builds do not automatically publish production downloads.

The repository is public. The website downloads published release assets without
`GAMI_RELEASE_READ_TOKEN`; a separate read credential is no longer needed.
GitHub Actions builds the website and uploads it with `netlify deploy`; Netlify
build hooks and Git integration are not used. The website downloads only the release's
approved distributables, validates them, and serves them publicly from its own
deployment. Installers are never committed to the website repository.

Deploy the companion website changes before the first release. They consume the
new manifest and verify Linux signatures; Windows signatures and timestamps are
verified on the signing runner. Existing test drafts are not stable releases.

Merge the website's dispatch listener into its default branch (`master`) first.
If dispatch fails after publication, fix the secret and run the website's Deploy
workflow manually on master. Do not recreate the release. Confirm the site deployment and
download hashes before announcing the release.

Local manifest tests: `node --test scripts/create-download-manifest.test.mjs`.
