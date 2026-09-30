#!/usr/bin/env bash
# Add a native RPM header signature using the same temporary release key as
# the detached download signatures. The package must be signed before hashes
# and detached signatures are generated.
set -euo pipefail
umask 077
: "${LINUX_SIGNING_PRIVATE_KEY:?Missing signing key}"
: "${LINUX_SIGNING_PASSPHRASE:?Missing signing passphrase}"
: "${LINUX_SIGNING_FINGERPRINT:?Missing primary fingerprint}"
[[ $# -ge 1 ]] || { echo 'Usage: sign-rpm.sh PACKAGE...' >&2; exit 1; }
[[ "$LINUX_SIGNING_FINGERPRINT" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'Expected a full primary key fingerprint' >&2; exit 1; }
work=$(mktemp -d)
trap 'gpgconf --homedir "$work/gnupg" --kill gpg-agent 2>/dev/null || true; rm -rf -- "$work"' EXIT
mkdir "$work/gnupg" "$work/rpmdb"
printf '%s' "$LINUX_SIGNING_PRIVATE_KEY" | gpg --homedir "$work/gnupg" --batch --quiet --import
fingerprint=$(gpg --homedir "$work/gnupg" --batch --with-colons --list-secret-keys | awk -F: '$1=="fpr" {print $10; exit}')
[[ "${fingerprint^^}" == "${LINUX_SIGNING_FINGERPRINT^^}" ]] || { echo 'Signing fingerprint mismatch' >&2; exit 1; }
gpg --homedir "$work/gnupg" --batch --armor --export "$fingerprint" > "$work/release-key.asc"
rpm --dbpath "$work/rpmdb" --import "$work/release-key.asc"
cat > "$work/gpg-wrapper" <<'EOF'
#!/usr/bin/env bash
exec gpg --homedir "${RPM_GNUPGHOME:?}" --batch --yes --pinentry-mode loopback --passphrase "${LINUX_SIGNING_PASSPHRASE:?}" "$@"
EOF
chmod 0700 "$work/gpg-wrapper"
export RPM_GNUPGHOME="$work/gnupg"
for package in "$@"; do
  [[ -f "$package" ]] || { echo "Missing RPM: $package" >&2; exit 1; }
  rpmsign --define "_gpg_path $RPM_GNUPGHOME" --define "_gpg_name $fingerprint" --define "__gpg $work/gpg-wrapper" --addsign --key-id "$fingerprint" "$package"
  rpm --dbpath "$work/rpmdb" --checksig --verbose "$package"
done
