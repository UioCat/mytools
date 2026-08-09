#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${MACTOOLS_APP_DIR:-/Applications/MacTools.app}"
LOG_FILE="$HOME/Library/Application Support/MacTools/debug.log"
CLEAR_LOG=0
PROBE=0

for arg in "$@"; do
  case "$arg" in
    --clear-log)
      CLEAR_LOG=1
      ;;
    --probe)
      PROBE=1
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "usage: $0 [--clear-log] [--probe]" >&2
      exit 2
      ;;
  esac
done

echo "== MacTools super right-click diagnostic =="
date "+time: %Y-%m-%d %H:%M:%S %z"
echo "repo: $ROOT_DIR"
echo "app:  $APP_DIR"
echo

if [[ -d "$APP_DIR" ]]; then
  echo "== Bundle =="
  /usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    | sed 's/^/bundle id: /' || true
  stat -f "binary modified: %Sm" -t "%Y-%m-%d %H:%M:%S %z" "$APP_DIR/Contents/MacOS/MacTools"
  echo

  echo "== Code signing =="
  codesign -d -r- "$APP_DIR" 2>&1 | sed 's/^/requirement: /' || true
  codesign -dv --verbose=2 "$APP_DIR" 2>&1 \
    | rg 'Identifier=|Signature=|TeamIdentifier=|Internal requirements' || true
  spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1 \
    | sed 's/^/spctl: /' || true
  security find-identity -v -p codesigning 2>/dev/null \
    | sed 's/^/identity: /' || true
  echo
else
  echo "app bundle missing; run scripts/rebuild_and_run_app.sh first"
  echo
fi

echo "== Running process =="
pgrep -fl "MacTools" || echo "MacTools is not running"
echo

if [[ "$CLEAR_LOG" -eq 1 ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  echo "cleared log: $LOG_FILE"
  echo
fi

if [[ "$PROBE" -eq 1 ]]; then
  echo "== Synthetic right-click probe =="
  swift -e 'import CoreGraphics; import Foundation; let source = CGEventSource(stateID: .hidSystemState); let loc = CGPoint(x: 600, y: 500); guard let down = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: loc, mouseButton: .right), let up = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: loc, mouseButton: .right) else { fatalError("failed to create right-click events") }; down.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.9); up.post(tap: .cghidEventTap)'
  sleep 1
  echo
fi

echo "== Recent MacTools log =="
if [[ -f "$LOG_FILE" ]]; then
  tail -160 "$LOG_FILE"
else
  echo "log file missing: $LOG_FILE"
fi
