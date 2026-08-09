#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIMEOUT_SCRIPT="$ROOT_DIR/scripts/ci/run_with_timeout.sh"
SECURITY_TIMEOUT_SECONDS=30

if [[ ! -x "$TIMEOUT_SCRIPT" ]]; then
  echo "error: bounded command helper is missing." >&2
  exit 1
fi

run_security() {
  "$TIMEOUT_SCRIPT" "$SECURITY_TIMEOUT_SECONDS" security "$@"
}

if [[ "$#" -lt 2 ]]; then
  echo "usage: $0 <prepend|restore> <state-file> [signing-keychain]" >&2
  exit 64
fi

MODE="$1"
STATE_FILE="$2"

normalize_keychain_path() {
  sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
}

read_state_file() {
  local line
  KEYCHAINS=()
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      KEYCHAINS+=("$line")
    fi
  done < "$STATE_FILE"
  if [[ "${#KEYCHAINS[@]}" -eq 0 ]]; then
    echo "error: saved user keychain search list is empty." >&2
    return 1
  fi
}

case "$MODE" in
  prepend)
    if [[ "$#" -ne 3 ]]; then
      echo "usage: $0 prepend <state-file> <signing-keychain>" >&2
      exit 64
    fi
    SIGNING_KEYCHAIN="$3"
    if [[ -e "$STATE_FILE" ]]; then
      echo "error: user keychain search-list state already exists." >&2
      exit 1
    fi
    if ! ORIGINAL_LIST_OUTPUT="$(run_security list-keychains -d user)"; then
      echo "error: unable to read the original user keychain search list." >&2
      exit 1
    fi

    ORIGINAL_KEYCHAINS=()
    PREPENDED_KEYCHAINS=("$SIGNING_KEYCHAIN")
    while IFS= read -r line; do
      line="$(normalize_keychain_path <<<"$line")"
      if [[ -n "$line" ]]; then
        ORIGINAL_KEYCHAINS+=("$line")
        if [[ "$line" != "$SIGNING_KEYCHAIN" ]]; then
          PREPENDED_KEYCHAINS+=("$line")
        fi
      fi
    done <<< "$ORIGINAL_LIST_OUTPUT"
    if [[ "${#ORIGINAL_KEYCHAINS[@]}" -eq 0 ]]; then
      echo "error: original user keychain search list is empty." >&2
      exit 1
    fi

    PENDING_STATE_FILE="$STATE_FILE.pending.$$"
    cleanup_pending_state() {
      if [[ -f "$PENDING_STATE_FILE" ]]; then
        unlink "$PENDING_STATE_FILE" || true
      fi
    }
    trap cleanup_pending_state EXIT
    (umask 077 && printf '%s\n' "${ORIGINAL_KEYCHAINS[@]}" > "$PENDING_STATE_FILE")
    mv "$PENDING_STATE_FILE" "$STATE_FILE"
    trap - EXIT

    if ! run_security list-keychains -d user -s "${PREPENDED_KEYCHAINS[@]}"; then
      echo "error: unable to prepend the temporary signing keychain." >&2
      exit 1
    fi
    ;;
  restore)
    if [[ "$#" -ne 2 ]]; then
      echo "usage: $0 restore <state-file>" >&2
      exit 64
    fi
    if [[ ! -f "$STATE_FILE" ]]; then
      exit 0
    fi
    read_state_file
    if ! run_security list-keychains -d user -s "${KEYCHAINS[@]}"; then
      echo "error: unable to restore the original user keychain search list." >&2
      exit 1
    fi
    unlink "$STATE_FILE"
    ;;
  *)
    echo "error: mode must be prepend or restore." >&2
    exit 64
    ;;
esac
