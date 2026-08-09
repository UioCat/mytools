#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <private-key-output.pem>" >&2
  exit 64
fi

OUTPUT_PATH="$1"
OUTPUT_DIRECTORY="$(cd "$(dirname "$OUTPUT_PATH")" && pwd)"
DER_OUTPUT="$OUTPUT_PATH.der"

cleanup() {
  local status="$?"
  trap - EXIT
  [[ ! -f "$DER_OUTPUT" ]] || unlink "$DER_OUTPUT"
  if [[ "$status" -ne 0 && -f "$OUTPUT_PATH" ]]; then
    unlink "$OUTPUT_PATH"
  fi
  exit "$status"
}
trap cleanup EXIT

if [[ -e "$OUTPUT_PATH" || -e "$DER_OUTPUT" ]]; then
  echo "error: derived signing key output already exists." >&2
  exit 1
fi

if [[ "$(stat -f '%Lp' "$OUTPUT_DIRECTORY")" != "700" ]]; then
  echo "error: derived signing key output directory must have mode 0700." >&2
  exit 1
fi

ROOT_SECRET="${SPARKLE_PRIVATE_KEY:-}"
if [[ -z "$ROOT_SECRET" || "$ROOT_SECRET" == *$'\n'* ]]; then
  echo "error: SPARKLE_PRIVATE_KEY must contain one non-empty line." >&2
  exit 1
fi

DECODED_ROOT_LENGTH="$({ printf '%s' "$ROOT_SECRET" | base64 -D | wc -c; } 2>/dev/null | tr -d ' ')"
if [[ "$DECODED_ROOT_LENGTH" != "32" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY does not contain a 32-byte Sparkle seed." >&2
  exit 1
fi

SALT_HEX="$(
  printf '%s' 'MacTools release root v1' \
    | xxd -p -c 256
)"
PRK_HEX="$(
  printf '%s' "$ROOT_SECRET" \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$SALT_HEX" \
    | awk '{ print $NF }'
)"
unset ROOT_SECRET SPARKLE_PRIVATE_KEY

if [[ ! "$PRK_HEX" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: unable to derive the anonymous signing root." >&2
  exit 1
fi

INFO_HEX="$(
  printf '%s' 'MacTools anonymous code signing P-256 v1' \
    | xxd -p -c 256
)"
P256_ORDER='ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551'
PREVIOUS_BLOCK_HEX=''
SCALAR_HEX=''

for COUNTER in {1..255}; do
  printf -v COUNTER_HEX '%02x' "$COUNTER"
  EXPAND_INPUT_HEX="${PREVIOUS_BLOCK_HEX}${INFO_HEX}${COUNTER_HEX}"
  CANDIDATE_HEX="$(
    printf '%s' "$EXPAND_INPUT_HEX" \
      | xxd -r -p \
      | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$PRK_HEX" \
      | awk '{ print $NF }'
  )"

  if [[ ! "$CANDIDATE_HEX" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: unable to expand the anonymous signing key." >&2
    exit 1
  fi

  if [[ "$CANDIDATE_HEX" != '0000000000000000000000000000000000000000000000000000000000000000' \
    && "$CANDIDATE_HEX" < "$P256_ORDER" ]]; then
    SCALAR_HEX="$CANDIDATE_HEX"
    break
  fi
  PREVIOUS_BLOCK_HEX="$CANDIDATE_HEX"
done

if [[ -z "$SCALAR_HEX" ]]; then
  echo "error: unable to derive a valid P-256 signing scalar." >&2
  exit 1
fi

umask 077
printf '30310201010420%sA00A06082A8648CE3D030107' "$SCALAR_HEX" \
  | xxd -r -p > "$DER_OUTPUT"
chmod 600 "$DER_OUTPUT"

unset PRK_HEX PREVIOUS_BLOCK_HEX CANDIDATE_HEX SCALAR_HEX EXPAND_INPUT_HEX

openssl ec \
  -inform DER \
  -in "$DER_OUTPUT" \
  -out "$OUTPUT_PATH" \
  >/dev/null 2>&1
chmod 600 "$OUTPUT_PATH"
openssl ec -in "$OUTPUT_PATH" -check -noout >/dev/null 2>&1

printf 'Derived anonymous P-256 signing key.\n'
