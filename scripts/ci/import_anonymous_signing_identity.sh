#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PINNED_CERTIFICATE="$ROOT_DIR/scripts/signing/MacToolsReleaseSigning.pem"
DERIVATION_SCRIPT="$ROOT_DIR/scripts/signing/derive_anonymous_signing_private_key.sh"
KEYCHAIN_SEARCH_LIST_SCRIPT="$ROOT_DIR/scripts/ci/manage_keychain_search_list.sh"
SIGNING_IDENTITY="MacTools Release Signing"
EXPECTED_CERTIFICATE_SHA1="25A3263958804C6D9429EB51B97BA2B16CA1FB67"
EXPECTED_CERTIFICATE_SHA256="D098182A8CFA254D9834F5E0E7911C39418080D38B1AC921E8F90E90DDE3E157"
EXPECTED_PUBLIC_KEY_SHA256="D5B6541A61CE08813F5FA2C36862B40AC0CD992F8D6352FDFB1EDF23231FACFE"

: "${RUNNER_TEMP:?RUNNER_TEMP is required.}"
: "${GITHUB_ENV:?GITHUB_ENV is required.}"

SIGNING_DIRECTORY="$RUNNER_TEMP/mactools-release-signing"
SIGNING_KEYCHAIN="$SIGNING_DIRECTORY/mactools-release-signing.keychain-db"
SIGNING_PRIVATE_KEY="$SIGNING_DIRECTORY/mactools-release-signing-private.pem"
SIGNING_P12="$SIGNING_DIRECTORY/mactools-release-signing.p12"
IMPORTED_CERTIFICATE="$SIGNING_DIRECTORY/mactools-release-signing-imported.pem"
SYSTEM_TRUST_OWNERSHIP_MARKER="$SIGNING_DIRECTORY/system-trust-owned"
ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE="$SIGNING_DIRECTORY/original-user-keychain-search-list"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY is required to derive the anonymous signing identity." >&2
  exit 1
fi

if [[ ! -f "$PINNED_CERTIFICATE" \
  || ! -x "$DERIVATION_SCRIPT" \
  || ! -x "$KEYCHAIN_SEARCH_LIST_SCRIPT" ]]; then
  echo "error: pinned certificate or signing helper script is missing." >&2
  exit 1
fi

if [[ -e "$SIGNING_DIRECTORY" ]]; then
  echo "error: anonymous signing temporary directory already exists." >&2
  exit 1
fi
mkdir "$SIGNING_DIRECTORY"
chmod 700 "$SIGNING_DIRECTORY"

"$DERIVATION_SCRIPT" "$SIGNING_PRIVATE_KEY"
unset SPARKLE_PRIVATE_KEY

PINNED_SUBJECT="$(
  openssl x509 -in "$PINNED_CERTIFICATE" -noout -subject -nameopt RFC2253 \
    | sed -E 's/^subject=[[:space:]]*/subject=/'
)"
PINNED_SHA256="$(
  openssl x509 -in "$PINNED_CERTIFICATE" -noout -fingerprint -sha256 \
    | cut -d= -f2 \
    | tr -d ':'
)"
PINNED_SHA1="$(
  openssl x509 -in "$PINNED_CERTIFICATE" -noout -fingerprint -sha1 \
    | cut -d= -f2 \
    | tr -d ':'
)"
PINNED_PUBLIC_KEY_SHA256="$(
  openssl x509 -in "$PINNED_CERTIFICATE" -pubkey -noout \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | shasum -a 256 \
    | awk '{ print toupper($1) }'
)"
DERIVED_PUBLIC_KEY_SHA256="$(
  openssl ec -in "$SIGNING_PRIVATE_KEY" -pubout -outform DER 2>/dev/null \
    | shasum -a 256 \
    | awk '{ print toupper($1) }'
)"

if [[ "$PINNED_SUBJECT" != "subject=CN=$SIGNING_IDENTITY" ]]; then
  echo "error: pinned signing certificate has an unexpected subject." >&2
  exit 1
fi

if [[ "$PINNED_SHA1" != "$EXPECTED_CERTIFICATE_SHA1" \
  || "$PINNED_SHA256" != "$EXPECTED_CERTIFICATE_SHA256" ]]; then
  echo "error: pinned signing certificate fingerprint does not match the fixed identity." >&2
  exit 1
fi

if [[ "$PINNED_PUBLIC_KEY_SHA256" != "$EXPECTED_PUBLIC_KEY_SHA256" \
  || "$DERIVED_PUBLIC_KEY_SHA256" != "$EXPECTED_PUBLIC_KEY_SHA256" ]]; then
  echo "error: derived signing key does not match the pinned public certificate." >&2
  exit 1
fi

if ! openssl x509 -in "$PINNED_CERTIFICATE" -noout -text \
  | grep -F 'Public Key Algorithm: id-ecPublicKey' >/dev/null; then
  echo "error: pinned signing certificate is not a P-256 EC certificate." >&2
  exit 1
fi

P12_PASSWORD="$(openssl rand -base64 48 | tr -d '\n')"
KEYCHAIN_PASSWORD="$(openssl rand -base64 48 | tr -d '\n')"

P12_PASSWORD="$P12_PASSWORD" openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$SIGNING_PRIVATE_KEY" \
  -in "$PINNED_CERTIFICATE" \
  -name "$SIGNING_IDENTITY" \
  -passout env:P12_PASSWORD \
  -out "$SIGNING_P12"
chmod 600 "$SIGNING_P12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security import "$SIGNING_P12" \
  -k "$SIGNING_KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$SIGNING_KEYCHAIN" >/dev/null

security find-certificate \
  -c "$SIGNING_IDENTITY" \
  -p \
  "$SIGNING_KEYCHAIN" > "$IMPORTED_CERTIFICATE"
chmod 600 "$IMPORTED_CERTIFICATE"

IMPORTED_SHA256="$(
  openssl x509 -in "$IMPORTED_CERTIFICATE" -noout -fingerprint -sha256 \
    | cut -d= -f2 \
    | tr -d ':'
)"
if [[ "$IMPORTED_SHA256" != "$EXPECTED_CERTIFICATE_SHA256" ]]; then
  echo "error: imported signing identity does not match the pinned certificate." >&2
  exit 1
fi

if ! security verify-cert -p codeSign -c "$PINNED_CERTIFICATE" >/dev/null 2>&1; then
  if ! SYSTEM_KEYCHAIN_CERTIFICATES="$(
    security find-certificate \
      -a \
      -Z \
      /Library/Keychains/System.keychain 2>/dev/null
  )"; then
    echo "error: unable to inspect the system keychain before adding temporary trust." >&2
    exit 1
  fi
  if grep -F "$PINNED_SHA1" <<<"$SYSTEM_KEYCHAIN_CERTIFICATES" >/dev/null; then
    echo "error: pinned certificate already exists in the system keychain without valid code-signing trust." >&2
    exit 1
  fi
  if ! (umask 077 && : > "$SYSTEM_TRUST_OWNERSHIP_MARKER"); then
    echo "error: unable to record ownership before adding temporary system trust." >&2
    exit 1
  fi
  sudo security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "$PINNED_CERTIFICATE"
fi

if ! security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" \
  | grep -F "$PINNED_SHA1" \
  | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
  echo "error: derived identity is not valid for code signing." >&2
  exit 1
fi

for SENSITIVE_FILE in "$SIGNING_PRIVATE_KEY" "$SIGNING_P12"; do
  if ! unlink "$SENSITIVE_FILE"; then
    echo "error: unable to remove imported anonymous signing material." >&2
    exit 1
  fi
  if [[ -e "$SENSITIVE_FILE" ]]; then
    echo "error: imported anonymous signing material remains on disk." >&2
    exit 1
  fi
done

"$KEYCHAIN_SEARCH_LIST_SCRIPT" \
  prepend \
  "$ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE" \
  "$SIGNING_KEYCHAIN"

{
  printf 'MACOS_CODESIGN_KEYCHAIN=%s\n' "$SIGNING_KEYCHAIN"
  printf 'MACTOOLS_CI_SIGNING_DIRECTORY=%s\n' "$SIGNING_DIRECTORY"
  printf 'MACTOOLS_CI_SIGNING_KEYCHAIN=%s\n' "$SIGNING_KEYCHAIN"
  printf 'MACTOOLS_CI_IMPORTED_CERTIFICATE=%s\n' "$IMPORTED_CERTIFICATE"
  printf 'MACTOOLS_CI_ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE=%s\n' \
    "$ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE"
  printf 'MACTOOLS_CI_SYSTEM_TRUST_OWNERSHIP_MARKER=%s\n' \
    "$SYSTEM_TRUST_OWNERSHIP_MARKER"
} >> "$GITHUB_ENV"

printf 'Imported derived anonymous signing certificate SHA-256: %s\n' "$PINNED_SHA256"
