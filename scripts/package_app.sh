#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/MacTools.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
BUNDLE_ID="local.mactools.mvp"

swift build -c release --product MacTools

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/MacTools" "$MACOS_DIR/MacTools"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacTools</string>
  <key>CFBundleIdentifier</key>
  <string>local.mactools.mvp</string>
  <key>CFBundleName</key>
  <string>MacTools</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

CODESIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/Developer ID Application|Apple Development|Mac Developer/ { print $2; exit }'
  )"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "Signing with identity: $CODESIGN_IDENTITY" >&2
  codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --requirements "=designated => identifier \"$BUNDLE_ID\" and anchor trusted" \
    "$APP_DIR"
else
  echo "warning: no trusted code signing identity found; using ad-hoc signing." >&2
  echo "warning: macOS TCC may not reliably match Accessibility/Input Monitoring grants for this build." >&2
  codesign \
    --force \
    --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR"
fi

echo "$APP_DIR"
