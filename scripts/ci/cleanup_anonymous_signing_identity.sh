#!/usr/bin/env bash
set -uo pipefail

CLEANUP_STATUS=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PINNED_CERTIFICATE="$ROOT_DIR/scripts/signing/MacToolsReleaseSigning.pem"
KEYCHAIN_SEARCH_LIST_SCRIPT="$ROOT_DIR/scripts/ci/manage_keychain_search_list.sh"
SIGNING_DIRECTORY="${MACTOOLS_CI_SIGNING_DIRECTORY:-${RUNNER_TEMP:-/tmp}/mactools-release-signing}"
SIGNING_KEYCHAIN="${MACTOOLS_CI_SIGNING_KEYCHAIN:-$SIGNING_DIRECTORY/mactools-release-signing.keychain-db}"
SIGNING_PRIVATE_KEY="${MACTOOLS_CI_SIGNING_PRIVATE_KEY:-$SIGNING_DIRECTORY/mactools-release-signing-private.pem}"
SIGNING_P12="${MACTOOLS_CI_SIGNING_P12:-$SIGNING_DIRECTORY/mactools-release-signing.p12}"
IMPORTED_CERTIFICATE="${MACTOOLS_CI_IMPORTED_CERTIFICATE:-$SIGNING_DIRECTORY/mactools-release-signing-imported.pem}"
SYSTEM_TRUST_OWNERSHIP_MARKER="${MACTOOLS_CI_SYSTEM_TRUST_OWNERSHIP_MARKER:-$SIGNING_DIRECTORY/system-trust-owned}"
ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE="${MACTOOLS_CI_ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE:-$SIGNING_DIRECTORY/original-user-keychain-search-list}"

if [[ -f "$SYSTEM_TRUST_OWNERSHIP_MARKER" && -f "$PINNED_CERTIFICATE" ]]; then
  PINNED_SHA1="$(
    openssl x509 -in "$PINNED_CERTIFICATE" -noout -fingerprint -sha1 \
      | cut -d= -f2 \
      | tr -d ':'
  )"
  TRUST_SETTINGS_REMOVAL_SUCCEEDED=1
  if ! sudo security remove-trusted-cert \
    -d \
    "$PINNED_CERTIFICATE" >/dev/null 2>&1; then
    echo "error: unable to remove temporary system trust settings." >&2
    CLEANUP_STATUS=1
    TRUST_SETTINGS_REMOVAL_SUCCEEDED=0
  fi
  sudo security delete-certificate \
    -Z "$PINNED_SHA1" \
    /Library/Keychains/System.keychain >/dev/null 2>&1 || true

  if ! SYSTEM_KEYCHAIN_CERTIFICATES="$(
    security find-certificate \
      -a \
      -Z \
      /Library/Keychains/System.keychain 2>/dev/null
  )"; then
    echo "error: unable to verify system keychain cleanup." >&2
    CLEANUP_STATUS=1
  elif grep -F "$PINNED_SHA1" <<<"$SYSTEM_KEYCHAIN_CERTIFICATES" >/dev/null; then
    echo "error: anonymous signing certificate remains in the system keychain." >&2
    CLEANUP_STATUS=1
  elif [[ "$TRUST_SETTINGS_REMOVAL_SUCCEEDED" != "1" ]]; then
    : # 保留所有权标记，供后续清理重试。
  elif security verify-cert \
    -p codeSign \
    -c "$PINNED_CERTIFICATE" >/dev/null 2>&1; then
    echo "error: anonymous signing certificate remains trusted for code signing." >&2
    CLEANUP_STATUS=1
  elif ! unlink "$SYSTEM_TRUST_OWNERSHIP_MARKER"; then
    echo "error: unable to remove system trust ownership marker." >&2
    CLEANUP_STATUS=1
  fi
fi

if [[ -f "$SIGNING_KEYCHAIN" ]]; then
  if ! security delete-keychain "$SIGNING_KEYCHAIN" >/dev/null 2>&1; then
    echo "error: unable to delete the anonymous signing keychain." >&2
    CLEANUP_STATUS=1
  fi
fi

if [[ -f "$ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE" ]]; then
  if [[ ! -x "$KEYCHAIN_SEARCH_LIST_SCRIPT" ]] \
    || ! "$KEYCHAIN_SEARCH_LIST_SCRIPT" restore "$ORIGINAL_KEYCHAIN_SEARCH_LIST_STATE"; then
    echo "error: unable to restore the saved user keychain search list." >&2
    CLEANUP_STATUS=1
  fi
fi

for SENSITIVE_FILE in "$SIGNING_PRIVATE_KEY" "$SIGNING_P12" "$IMPORTED_CERTIFICATE"; do
  if [[ -f "$SENSITIVE_FILE" ]] && ! unlink "$SENSITIVE_FILE"; then
    echo "error: unable to remove anonymous signing temporary material." >&2
    CLEANUP_STATUS=1
  fi
  if [[ -e "$SENSITIVE_FILE" ]]; then
    echo "error: anonymous signing temporary material remains on disk." >&2
    CLEANUP_STATUS=1
  fi
done

if [[ -d "$SIGNING_DIRECTORY" ]]; then
  if ! rmdir "$SIGNING_DIRECTORY" >/dev/null 2>&1; then
    echo "error: anonymous signing temporary directory is not empty." >&2
    CLEANUP_STATUS=1
  fi
fi

exit "$CLEANUP_STATUS"
