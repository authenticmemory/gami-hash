#!/usr/bin/env bash
# Detached OpenPGP signatures for direct downloads; not native RPM/APT signing.
set -euo pipefail
umask 077
: "${LINUX_SIGNING_PRIVATE_KEY:?Missing signing key}"
: "${LINUX_SIGNING_PASSPHRASE:?Missing signing passphrase}"
: "${LINUX_SIGNING_FINGERPRINT:?Missing primary fingerprint}"
[[ "$LINUX_SIGNING_FINGERPRINT" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'Expected a full primary key fingerprint' >&2; exit 1; }
[[ $# -ge 2 ]] || { echo 'Usage: sign-linux.sh OUTPUT_DIRECTORY FILE...' >&2; exit 1; }
out="$1"; shift
mkdir -p "$out"
work=$(mktemp -d)
trap 'gpgconf --homedir "$work/sign" --kill gpg-agent 2>/dev/null || true; rm -rf -- "$work"' EXIT
mkdir "$work/sign" "$work/verify"
printf '%s' "$LINUX_SIGNING_PRIVATE_KEY" | gpg --homedir "$work/sign" --batch --quiet --import
fingerprint=$(gpg --homedir "$work/sign" --batch --with-colons --list-secret-keys | awk -F: '$1=="fpr" {print $10; exit}')
[[ "${fingerprint^^}" == "${LINUX_SIGNING_FINGERPRINT^^}" ]] || { echo 'Signing fingerprint mismatch' >&2; exit 1; }
gpg --homedir "$work/sign" --batch --armor --export "$fingerprint" > "$out/gami-linux-signing-key.asc"
gpg --homedir "$work/verify" --batch --quiet --import "$out/gami-linux-signing-key.asc"
for file in "$@"; do
  [[ -f "$file" ]] || { echo "Missing artifact: $file" >&2; exit 1; }
  printf '%s\n' "$LINUX_SIGNING_PASSPHRASE" | gpg --homedir "$work/sign" --batch --yes --pinentry-mode loopback --passphrase-fd 0 --local-user "$fingerprint" --armor --detach-sign --output "$file.asc" "$file"
  gpg --homedir "$work/verify" --batch --verify "$file.asc" "$file"
done
printf '%s\n' "$fingerprint" > "$out/gami-linux-signing-fingerprint.txt"
