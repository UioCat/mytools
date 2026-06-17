#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTools"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
APP_EXEC="$APP_DIR/Contents/MacOS/$APP_NAME"
BUNDLE_ID="local.mactools.mvp"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_app.sh"
LAUNCH_LOG="$ROOT_DIR/build/$APP_NAME.launch.log"

wait_for_app_process() {
  for _ in {1..30}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

launch_with_open() {
  local launch_output
  launch_output="$(mktemp -t mactools-open.XXXXXX)"

  if open "$APP_DIR" >"$launch_output" 2>&1 && wait_for_app_process; then
    rm -f "$launch_output"
    return 0
  fi

  local open_status=$?
  echo "warning: open failed or app did not appear (status: $open_status)" >&2
  sed -n '1,20p' "$launch_output" >&2 || true
  rm -f "$launch_output"
  return 1
}

refresh_launch_services_registration() {
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$APP_DIR" >/dev/null 2>&1 || true
  fi
}

launch_directly() {
  if [[ ! -x "$APP_EXEC" ]]; then
    echo "error: expected executable not found at $APP_EXEC" >&2
    return 1
  fi

  echo "warning: LaunchServices failed; launching executable directly" >&2
  nohup "$APP_EXEC" >"$LAUNCH_LOG" 2>&1 &

  if wait_for_app_process; then
    return 0
  fi

  echo "error: direct launch did not start $APP_NAME; see $LAUNCH_LOG" >&2
  return 1
}

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
if ! launch_with_open; then
  echo "==> Refreshing LaunchServices registration"
  refresh_launch_services_registration

  if ! launch_with_open; then
    launch_directly
  fi
fi

echo "Relaunched $APP_NAME"
