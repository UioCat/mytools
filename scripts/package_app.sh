#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/MacTools.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLE_ID="local.mactools.mvp"
APP_VERSION="${MACOS_APP_VERSION:-0.1.0}"
BUILD_NUMBER="${MACOS_BUILD_NUMBER:-1}"
FORCE_ADHOC_SIGNING="${MACOS_FORCE_ADHOC_SIGNING:-0}"

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: MACOS_APP_VERSION must contain one to three numeric components." >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: MACOS_BUILD_NUMBER must contain one to three numeric components." >&2
  exit 1
fi

if [[ "$FORCE_ADHOC_SIGNING" != "0" && "$FORCE_ADHOC_SIGNING" != "1" ]]; then
  echo "error: MACOS_FORCE_ADHOC_SIGNING must be 0 or 1." >&2
  exit 1
fi

swift build -c release --product MacTools

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/MacTools" "$MACOS_DIR/MacTools"
cp "$ROOT_DIR/Sources/MacTools/Resources/MenuBarIcon.png" "$RESOURCES_DIR/MenuBarIcon.png"

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
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>用于读取访达当前窗口目录，以显示超级右键的目录操作。</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

CODESIGN_IDENTITY=""
if [[ "$FORCE_ADHOC_SIGNING" == "0" ]]; then
  CODESIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Developer ID Application|Apple Development|Mac Developer/ { print $2; exit }'
    )"
  fi
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
