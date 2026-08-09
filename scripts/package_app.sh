#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER_SCRIPT="$ROOT_DIR/scripts/macos_build_number.sh"
SIGNING_MODE="${MACOS_SIGNING_MODE:-development}"
APP_VERSION="${MACOS_APP_VERSION:-0.3.0}"
BUILD_NUMBER="${MACOS_BUILD_NUMBER:-$("$BUILD_NUMBER_SCRIPT" "$APP_VERSION")}"
SPARKLE_PUBLIC_KEY="${MACOS_SPARKLE_PUBLIC_KEY:-yLe/vkXicHCaK5ckGlBofZee559tbU22/q8Q8FWmDWc=}"
STABLE_SIGNING_IDENTITY="MacTools Release Signing"
STABLE_CERTIFICATE_PATH="$ROOT_DIR/scripts/signing/MacToolsReleaseSigning.pem"
MAIN_APP_ENTITLEMENTS="$ROOT_DIR/scripts/signing/MacToolsNoTeamID.entitlements"
EXPECTED_CERTIFICATE_SHA1="25A3263958804C6D9429EB51B97BA2B16CA1FB67"
EXPECTED_CERTIFICATE_SHA256="D098182A8CFA254D9834F5E0E7911C39418080D38B1AC921E8F90E90DDE3E157"
CODESIGN_KEYCHAIN="${MACOS_CODESIGN_KEYCHAIN:-}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacTools-release.XXXXXX")"

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

case "$SIGNING_MODE" in
  stable)
    BUNDLE_ID="local.mactools.mvp"
    APP_DISPLAY_NAME="MacTools"
    APP_BUNDLE_NAME="MacTools.app"
    ;;
  development)
    BUNDLE_ID="local.mactools.development"
    APP_DISPLAY_NAME="MacTools Dev"
    APP_BUNDLE_NAME="MacTools Dev.app"
    ;;
  *)
    echo "error: MACOS_SIGNING_MODE must be stable or development." >&2
    exit 1
    ;;
esac

APP_DIR="$ROOT_DIR/build/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

CODESIGN_ARGUMENTS=(--force --options runtime)

if [[ ! -f "$MAIN_APP_ENTITLEMENTS" ]]; then
  echo "error: no-Team-ID main app entitlements are missing: $MAIN_APP_ENTITLEMENTS" >&2
  exit 1
fi

if [[ "$SIGNING_MODE" == "stable" ]]; then
  if [[ ! -f "$STABLE_CERTIFICATE_PATH" ]]; then
    echo "error: pinned stable certificate is missing: $STABLE_CERTIFICATE_PATH" >&2
    exit 1
  fi

  CERTIFICATE_SUBJECT="$(
    openssl x509 -in "$STABLE_CERTIFICATE_PATH" -noout -subject -nameopt RFC2253 \
      | sed -E 's/^subject=[[:space:]]*/subject=/'
  )"
  if [[ "$CERTIFICATE_SUBJECT" != "subject=CN=$STABLE_SIGNING_IDENTITY" ]]; then
    echo "error: pinned stable certificate contains an unexpected subject." >&2
    exit 1
  fi

  CERTIFICATE_SHA1="$(
    openssl x509 -in "$STABLE_CERTIFICATE_PATH" -noout -fingerprint -sha1 \
      | cut -d= -f2 \
      | tr -d ':'
  )"
  CERTIFICATE_SHA256="$(
    openssl x509 -in "$STABLE_CERTIFICATE_PATH" -noout -fingerprint -sha256 \
      | cut -d= -f2 \
      | tr -d ':'
  )"
  if [[ "$CERTIFICATE_SHA1" != "$EXPECTED_CERTIFICATE_SHA1" \
    || "$CERTIFICATE_SHA256" != "$EXPECTED_CERTIFICATE_SHA256" ]]; then
    echo "error: pinned stable certificate fingerprint does not match the fixed identity." >&2
    exit 1
  fi

  if [[ -n "$CODESIGN_KEYCHAIN" ]]; then
    if [[ ! -f "$CODESIGN_KEYCHAIN" ]]; then
      echo "error: MACOS_CODESIGN_KEYCHAIN does not exist: $CODESIGN_KEYCHAIN" >&2
      exit 1
    fi
    CODESIGN_ARGUMENTS+=(--keychain "$CODESIGN_KEYCHAIN")
    VALID_SIGNING_IDENTITIES="$(
      security find-identity -v -p codesigning "$CODESIGN_KEYCHAIN"
    )"
  else
    VALID_SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"
  fi

  if ! grep -F "$EXPECTED_CERTIFICATE_SHA1" <<<"$VALID_SIGNING_IDENTITIES" \
    | grep -F "\"$STABLE_SIGNING_IDENTITY\"" >/dev/null; then
    echo "error: stable signing identity is unavailable or not trusted for code signing." >&2
    echo "error: expected $STABLE_SIGNING_IDENTITY ($EXPECTED_CERTIFICATE_SHA1)." >&2
    exit 1
  fi

  CODESIGN_ARGUMENTS+=(--sign "$EXPECTED_CERTIFICATE_SHA1")
else
  echo "warning: development signing uses an isolated ad-hoc identity." >&2
  echo "warning: do not grant production TCC permissions to MacTools Dev." >&2
  CODESIGN_ARGUMENTS+=(--sign -)
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
  <key>CFBundleDisplayName</key>
  <string>MacTools</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
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
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_DISPLAY_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_DISPLAY_NAME" "$CONTENTS_DIR/Info.plist"
if [[ "$SIGNING_MODE" == "stable" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "$CONTENTS_DIR/Info.plist"
fi

SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/Current"

sign_sparkle_component() {
  local component="$1"
  shift

  codesign "${CODESIGN_ARGUMENTS[@]}" "$@" "$component"
}

verify_stable_component_signature() {
  local component="$1"

  codesign \
    --verify \
    --strict \
    --test-requirement "=certificate leaf = H\"$EXPECTED_CERTIFICATE_SHA1\"" \
    --verbose=2 \
    "$component"
}

sign_sparkle_component "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_sparkle_component \
  "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" \
  --preserve-metadata=entitlements
sign_sparkle_component "$SPARKLE_VERSION_DIR/Autoupdate"
sign_sparkle_component "$SPARKLE_VERSION_DIR/Updater.app"
sign_sparkle_component "$SPARKLE_FRAMEWORK"

if [[ "$SIGNING_MODE" == "stable" ]]; then
  verify_stable_component_signature "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  verify_stable_component_signature "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  verify_stable_component_signature "$SPARKLE_VERSION_DIR/Autoupdate"
  verify_stable_component_signature "$SPARKLE_VERSION_DIR/Updater.app"
  verify_stable_component_signature "$SPARKLE_FRAMEWORK"
fi

if [[ "$SIGNING_MODE" == "stable" ]]; then
  echo "Signing stable app with identity: $STABLE_SIGNING_IDENTITY" >&2
  STABLE_REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$EXPECTED_CERTIFICATE_SHA1\""
  codesign \
    "${CODESIGN_ARGUMENTS[@]}" \
    --entitlements "$MAIN_APP_ENTITLEMENTS" \
    --requirements "=designated => $STABLE_REQUIREMENT" \
    "$APP_DIR"
else
  codesign \
    "${CODESIGN_ARGUMENTS[@]}" \
    --entitlements "$MAIN_APP_ENTITLEMENTS" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$SIGNING_MODE" == "stable" ]]; then
  EMBEDDED_CERTIFICATE_PREFIX="$BUILD_DIR/embedded-stable-certificate-"
  codesign \
    --display \
    --extract-certificates="$EMBEDDED_CERTIFICATE_PREFIX" \
    "$APP_DIR" \
    2>/dev/null
  EMBEDDED_CERTIFICATE_SHA1="$(
    openssl x509 \
      -inform DER \
      -in "${EMBEDDED_CERTIFICATE_PREFIX}0" \
      -noout \
      -fingerprint \
      -sha1 \
      | cut -d= -f2 \
      | tr -d ':'
  )"
  if [[ "$EMBEDDED_CERTIFICATE_SHA1" != "$EXPECTED_CERTIFICATE_SHA1" ]]; then
    echo "error: signed app certificate does not match the pinned certificate." >&2
    exit 1
  fi

  codesign \
    --verify \
    --strict \
    --test-requirement "=$STABLE_REQUIREMENT" \
    --verbose=2 \
    "$APP_DIR"
  SIGNATURE_DETAILS="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
  grep -Fqx "Authority=$STABLE_SIGNING_IDENTITY" <<<"$SIGNATURE_DETAILS"
  if grep -Eqi '@|Apple Development|Developer ID' <<<"$SIGNATURE_DETAILS"; then
    echo "error: stable signature exposes an unexpected personal or Apple identity." >&2
    exit 1
  fi
  TEAM_IDENTIFIER_LINE="$(grep '^TeamIdentifier=' <<<"$SIGNATURE_DETAILS" || true)"
  if [[ -n "$TEAM_IDENTIFIER_LINE" && "$TEAM_IDENTIFIER_LINE" != "TeamIdentifier=not set" ]]; then
    echo "error: stable signature unexpectedly contains a TeamIdentifier." >&2
    exit 1
  fi
  printf 'Stable certificate SHA-256: %s\n' "$EXPECTED_CERTIFICATE_SHA256" >&2
else
  SIGNATURE_DETAILS="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
  grep -F 'Signature=adhoc' <<<"$SIGNATURE_DETAILS" >/dev/null
fi

LINKED_LIBRARIES="$(otool -L "$MACOS_DIR/MacTools")"
LOAD_COMMANDS="$(otool -l "$MACOS_DIR/MacTools")"
grep -F '@rpath/Sparkle.framework/' <<<"$LINKED_LIBRARIES" >/dev/null
grep -A2 'LC_RPATH' <<<"$LOAD_COMMANDS" \
  | grep -F '@executable_path/../Frameworks' >/dev/null

MAIN_APP_ENTITLEMENTS_DETAILS="$(codesign --display --entitlements :- "$APP_DIR" 2>/dev/null)"
grep -F '<key>com.apple.security.cs.disable-library-validation</key>' \
  <<<"$MAIN_APP_ENTITLEMENTS_DETAILS" >/dev/null

echo "$APP_DIR"
