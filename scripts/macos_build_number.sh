#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="${1:-}"

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: application version must contain one to three numeric components." >&2
  exit 1
fi

IFS='.' read -r MAJOR_VERSION MINOR_VERSION PATCH_VERSION <<< "$APP_VERSION"
MINOR_VERSION="${MINOR_VERSION:-0}"
PATCH_VERSION="${PATCH_VERSION:-0}"

if (( 10#$MAJOR_VERSION > 8999 )); then
  echo "error: major version must be at most 8999." >&2
  exit 1
fi

if (( 10#$MINOR_VERSION > 99 || 10#$PATCH_VERSION > 99 )); then
  echo "error: minor and patch versions must be at most 99." >&2
  exit 1
fi

# The 1000 offset places the new semantic build sequence above the legacy
# GitHub run-number sequence, whose latest published value is 7.
printf '%d.%d.%d\n' \
  "$((1000 + 10#$MAJOR_VERSION))" \
  "$((10#$MINOR_VERSION))" \
  "$((10#$PATCH_VERSION))"
