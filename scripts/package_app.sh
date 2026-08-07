#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacTools-release.XXXXXX")"
APP_DIR="$ROOT_DIR/build/MacTools.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUNDLE_ID="${MACOS_BUNDLE_ID:-local.mactools.mvp}"
APP_VERSION="${MACOS_APP_VERSION:-0.1.0}"
BUILD_NUMBER="${MACOS_BUILD_NUMBER:-1}"
FORCE_ADHOC_SIGNING="${MACOS_FORCE_ADHOC_SIGNING:-0}"
SPARKLE_PUBLIC_KEY="${MACOS_SPARKLE_PUBLIC_KEY:-yLe/vkXicHCaK5ckGlBofZee559tbU22/q8Q8FWmDWc=}"

cleanup_build_directory() {
  rm -rf -- "$BUILD_DIR"
}
trap cleanup_build_directory EXIT

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

swift build \
  --scratch-path "$BUILD_DIR" \
  -c release \
  --product MacTools \
  -Xswiftc -file-prefix-map \
  -Xswiftc "$ROOT_DIR=." \
  -Xswiftc -debug-prefix-map \
  -Xswiftc "$ROOT_DIR=."

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BUILD_DIR/release/MacTools" "$MACOS_DIR/MacTools"
if [[ ! -d "$BUILD_DIR/release/Sparkle.framework" ]]; then
  echo "error: Sparkle.framework was not produced by SwiftPM." >&2
  exit 1
fi
ditto "$BUILD_DIR/release/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS_DIR/MacTools"
cp "$ROOT_DIR/Sources/MacTools/Resources/MenuBarIcon.png" "$RESOURCES_DIR/MenuBarIcon.png"
cp "$ROOT_DIR/Sources/MacTools/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacTools</string>
  <key>CFBundleIdentifier</key>
  <string>local.mactools.mvp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
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
  <key>SUFeedURL</key>
  <string>https://github.com/UioCat/mytools/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>yLe/vkXicHCaK5ckGlBofZee559tbU22/q8Q8FWmDWc=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
  <key>SUSignedFeedFailureExpirationInterval</key>
  <integer>0</integer>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"

SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/Current"

sign_sparkle_component() {
  local component="$1"
  shift

  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime "$@" "$component"
  else
    codesign --force --sign - --options runtime "$@" "$component"
  fi
}

sign_sparkle_component "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_sparkle_component \
  "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" \
  --preserve-metadata=entitlements
sign_sparkle_component "$SPARKLE_VERSION_DIR/Autoupdate"
sign_sparkle_component "$SPARKLE_VERSION_DIR/Updater.app"
sign_sparkle_component "$SPARKLE_FRAMEWORK"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "Signing with identity: $CODESIGN_IDENTITY" >&2
  SIGN_ARGUMENTS=(--force --sign "$CODESIGN_IDENTITY" --options runtime)
  SIGN_ARGUMENTS+=(--requirements "=designated => identifier \"$BUNDLE_ID\" and anchor trusted" "$APP_DIR")
  codesign "${SIGN_ARGUMENTS[@]}"
else
  echo "warning: no trusted code signing identity found; using ad-hoc signing." >&2
  echo "warning: macOS TCC may not reliably match Accessibility/Input Monitoring grants for this build." >&2
  codesign \
    --force \
    --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
otool -L "$MACOS_DIR/MacTools" | grep -q '@rpath/Sparkle.framework/'
otool -l "$MACOS_DIR/MacTools" \
  | grep -A2 'LC_RPATH' \
  | grep -q '@executable_path/../Frameworks'

echo "$APP_DIR"
