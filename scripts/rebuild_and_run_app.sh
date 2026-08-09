#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTools"
SIGNING_MODE="${MACOS_SIGNING_MODE:-stable}"
CANONICAL_APP_DIR="/Applications/MacTools.app"
LEGACY_BUILD_APP_DIR="$ROOT_DIR/build/MacTools.app"
DEVELOPMENT_APP_DIR="$ROOT_DIR/build/MacTools Dev.app"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_app.sh"
LAUNCH_LOG="$ROOT_DIR/build/$APP_NAME.launch.log"
INSTALL_STAGING_DIR="/Applications/.MacTools.install.$$.app"
INSTALL_BACKUP_DIR="/Applications/.MacTools.backup.$$.app"
INSTALLED_NEW_APP=0
HAS_INSTALL_BACKUP=0
INSTALL_COMMITTED=0
INSTALL_TEMP_PATHS_OWNED=0

case "$SIGNING_MODE" in
  stable)
    BUNDLE_ID="local.mactools.mvp"
    PACKAGED_APP_DIR="$LEGACY_BUILD_APP_DIR"
    APP_DIR="$CANONICAL_APP_DIR"
    CONFLICTING_APP_EXEC="$DEVELOPMENT_APP_DIR/Contents/MacOS/$APP_NAME"
    ;;
  development)
    BUNDLE_ID="local.mactools.development"
    PACKAGED_APP_DIR="$DEVELOPMENT_APP_DIR"
    APP_DIR="$PACKAGED_APP_DIR"
    CONFLICTING_APP_EXEC="$CANONICAL_APP_DIR/Contents/MacOS/$APP_NAME"
    ;;
  *)
    echo "error: MACOS_SIGNING_MODE must be stable or development." >&2
    exit 1
    ;;
esac

APP_EXEC="$APP_DIR/Contents/MacOS/$APP_NAME"

cleanup_installation() {
  local status=$?

  if [[ "$INSTALL_TEMP_PATHS_OWNED" == "1" && -d "$INSTALL_STAGING_DIR" ]]; then
    rm -rf -- "$INSTALL_STAGING_DIR"
  fi

  if [[ "$SIGNING_MODE" == "stable" && "$INSTALL_COMMITTED" != "1" ]]; then
    if [[ "$INSTALLED_NEW_APP" == "1" && -d "$CANONICAL_APP_DIR" ]]; then
      rm -rf -- "$CANONICAL_APP_DIR"
    fi
    if [[ "$HAS_INSTALL_BACKUP" == "1" && -d "$INSTALL_BACKUP_DIR" ]]; then
      mv "$INSTALL_BACKUP_DIR" "$CANONICAL_APP_DIR"
    fi
  elif [[ "$SIGNING_MODE" == "stable" && -d "$INSTALL_BACKUP_DIR" ]]; then
    rm -rf -- "$INSTALL_BACKUP_DIR"
  fi

  return "$status"
}
trap cleanup_installation EXIT

wait_for_app_process() {
  for _ in {1..30}; do
    if target_app_is_running; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

target_app_process_ids() {
  app_process_ids_for_executable "$APP_EXEC"
}

app_process_ids_for_executable() {
  local executable_path="$1"
  local process_id
  local process_command

  while IFS= read -r process_id; do
    [[ -n "$process_id" ]] || continue
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null || true)"
    if [[ "$process_command" == "$executable_path" \
      || "$process_command" == "$executable_path "* ]]; then
      printf '%s\n' "$process_id"
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

ensure_no_conflicting_app() {
  local conflicting_process_ids
  conflicting_process_ids="$(conflicting_app_process_ids)"

  if [[ -n "$conflicting_process_ids" ]]; then
    echo "error: refusing to run both identities concurrently." >&2
    echo "error: quit the other MacTools process before rebuilding $SIGNING_MODE." >&2
    echo "error: expected other identity path: $CONFLICTING_APP_EXEC" >&2
    exit 1
  fi
}

conflicting_app_process_ids() {
  local process_id
  local process_command

  while IFS= read -r process_id; do
    [[ -n "$process_id" ]] || continue
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null || true)"
    if [[ "$process_command" != "$APP_EXEC" && "$process_command" != "$APP_EXEC "* ]]; then
      printf '%s\n' "$process_id"
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

target_app_is_running() {
  [[ -n "$(target_app_process_ids)" ]]
}

terminate_target_app() {
  local process_id
  local -a process_ids=()

  while IFS= read -r process_id; do
    [[ -n "$process_id" ]] || continue
    process_ids+=("$process_id")
  done < <(target_app_process_ids)

  if [[ "${#process_ids[@]}" -gt 0 ]]; then
    kill "${process_ids[@]}" >/dev/null 2>&1 || true
  fi
}

request_graceful_quit() {
  osascript >/dev/null 2>&1 <<OSA &
tell application id "$BUNDLE_ID" to quit
OSA
  local osascript_pid=$!

  for _ in {1..20}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.1
  done

  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" 2>/dev/null || true
}

stop_running_app() {
  echo "==> Stopping the $SIGNING_MODE app at $APP_EXEC"
  if ! target_app_is_running; then
    echo "No running $SIGNING_MODE $APP_NAME process found"
    return
  fi

  request_graceful_quit
  for _ in {1..20}; do
    if ! target_app_is_running; then
      return
    fi
    sleep 0.1
  done

  terminate_target_app
  for _ in {1..20}; do
    if ! target_app_is_running; then
      return
    fi
    sleep 0.1
  done

  echo "error: unable to stop the running $APP_NAME process." >&2
  exit 1
}

install_stable_app() {
  echo "==> Installing stable app at $CANONICAL_APP_DIR"
  if [[ -e "$INSTALL_STAGING_DIR" || -e "$INSTALL_BACKUP_DIR" ]]; then
    echo "error: temporary installation path already exists." >&2
    exit 1
  fi

  INSTALL_TEMP_PATHS_OWNED=1
  ditto "$PACKAGED_APP_DIR" "$INSTALL_STAGING_DIR"
  codesign --verify --deep --strict --verbose=2 "$INSTALL_STAGING_DIR"

  if [[ -e "$CANONICAL_APP_DIR" ]]; then
    mv "$CANONICAL_APP_DIR" "$INSTALL_BACKUP_DIR"
    HAS_INSTALL_BACKUP=1
  fi

  mv "$INSTALL_STAGING_DIR" "$CANONICAL_APP_DIR"
  INSTALLED_NEW_APP=1
}

launch_with_open() {
  local launch_output
  launch_output="$(mktemp -t mactools-open.XXXXXX)"
  local -a open_arguments=("$APP_DIR")

  if [[ "${MACTOOLS_UI_VERIFICATION_OPEN_SETTINGS:-0}" == "1" ]]; then
    open_arguments=("$APP_DIR" --args --ui-verification-open-settings)
    if [[ "${MACTOOLS_UI_VERIFICATION_DARK:-0}" == "1" ]]; then
      open_arguments+=(--ui-verification-dark)
    fi
  fi

  if open "${open_arguments[@]}" >"$launch_output" 2>&1 && wait_for_app_process; then
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

ensure_no_conflicting_app

echo "==> Building $PACKAGED_APP_DIR in $SIGNING_MODE mode"
MACOS_SIGNING_MODE="$SIGNING_MODE" "$PACKAGE_SCRIPT"

if [[ ! -d "$PACKAGED_APP_DIR" ]]; then
  echo "error: expected app bundle not found at $PACKAGED_APP_DIR" >&2
  exit 1
fi

ensure_no_conflicting_app

stop_running_app

if [[ "$SIGNING_MODE" == "stable" ]]; then
  install_stable_app
fi

echo "==> Launching $APP_DIR"
if ! launch_with_open; then
  echo "==> Refreshing LaunchServices registration"
  refresh_launch_services_registration

  if ! launch_with_open; then
    launch_directly
  fi
fi

INSTALL_COMMITTED=1
echo "Relaunched $APP_NAME from $APP_DIR"
