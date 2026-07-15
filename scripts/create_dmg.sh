#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTools"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
VERSION="${1:-}"
ARCHITECTURE="${2:-$(uname -m)}"
OUTPUT_DIR="${MACOS_DMG_OUTPUT_DIR:-$ROOT_DIR/dist}"

if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/create_dmg.sh <version> [architecture]" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: version must contain one to three numeric components." >&2
  exit 1
fi

if [[ ! "$ARCHITECTURE" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "error: architecture contains unsupported characters." >&2
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: expected app bundle not found at $APP_DIR" >&2
  echo "error: run scripts/package_app.sh before creating the DMG." >&2
  exit 1
fi

DMG_NAME="$APP_NAME-v$VERSION-$ARCHITECTURE-macos26.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
TEMP_DMG_PATH="$OUTPUT_DIR/.${DMG_NAME%.dmg}.$$.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mactools-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
  rm -f "$TEMP_DMG_PATH"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$TEMP_DMG_PATH"

mv -f "$TEMP_DMG_PATH" "$DMG_PATH"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "$DMG_PATH"
echo "$DMG_PATH.sha256"
