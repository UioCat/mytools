#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTools"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BUNDLE_ID="local.mactools.mvp"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_app.sh"

echo "==> Building $APP_NAME.app"
"$PACKAGE_SCRIPT"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: expected app bundle not found at $APP_DIR" >&2
  exit 1
fi

echo "==> Stopping any running $APP_NAME"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  osascript >/dev/null 2>&1 <<OSA || true
tell application id "$BUNDLE_ID" to quit
OSA

  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME" || true
    for _ in {1..20}; do
      if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
  fi
else
  echo "No running $APP_NAME process found"
fi

echo "==> Launching $APP_DIR"
open "$APP_DIR"

echo "Relaunched $APP_NAME"
