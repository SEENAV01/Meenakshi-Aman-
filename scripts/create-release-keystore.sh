#!/usr/bin/env bash
# Creates the ONE release signing key for Gyanify and prints the four values to
# paste into GitHub secrets. Run it once, in your Codespace terminal:
#
#   bash scripts/create-release-keystore.sh
#
# Output goes to .release-keys/ (git-ignored, never committed):
#   gyanify-release.jks   keep a backup copy safe (Google Drive / pen drive).
#                         If it is lost, students must uninstall to get updates.
#   github-secrets.txt    the four values for GitHub secrets. Delete it after use.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.release-keys}"
keystore="$out_dir/gyanify-release.jks"
secrets_file="$out_dir/github-secrets.txt"
alias_name="gyanify"

command -v keytool >/dev/null || { echo "keytool (Java) is not installed." >&2; exit 1; }

if [ -e "$keystore" ]; then
  echo "A key already exists at $keystore. Not overwriting it." >&2
  echo "Use the existing one (see $secrets_file), or move it away first." >&2
  exit 1
fi

mkdir -p "$out_dir"
chmod 700 "$out_dir"
if [ -z "${OUT_DIR:-}" ] && ! git -C "$repo_root" check-ignore -q "$keystore"; then
  echo "Refusing to continue: $keystore is not git-ignored." >&2
  exit 1
fi

# PKCS12 keystores use one password for the store and the key.
# (pipefail off here: head closing the pipe early is expected.)
password="$(set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"

keytool -genkeypair -noprompt \
  -keystore "$keystore" -storetype PKCS12 \
  -alias "$alias_name" -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$password" -keypass "$password" \
  -dname "CN=Gyanify, O=Gyanify, C=IN" >/dev/null 2>&1
chmod 600 "$keystore"

umask 077
{
  echo "Add these 4 secrets in GitHub: Settings > Secrets and variables > Actions > New repository secret"
  echo "Name on the left, value on the right. Copy the value exactly, with no spaces."
  echo
  echo "ANDROID_KEY_ALIAS"
  echo "$alias_name"
  echo
  echo "ANDROID_KEYSTORE_PASSWORD"
  echo "$password"
  echo
  echo "ANDROID_KEY_PASSWORD"
  echo "$password"
  echo
  echo "ANDROID_KEYSTORE_BASE64   (one very long line, copy all of it)"
  base64 -w0 "$keystore"
  echo
} > "$secrets_file"

echo "Done."
echo "  Key file:     $keystore   (download a backup copy)"
echo "  Secret values: $secrets_file"
echo "Open the values with:  code \"$secrets_file\""
