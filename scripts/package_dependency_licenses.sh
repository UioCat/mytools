#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: package_dependency_licenses.sh BUILD_DIR RESOURCES_DIR" >&2
  exit 1
fi

DEPENDENCY_BUILD_DIR="$1"
LICENSE_RESOURCES_DIR="$2/ThirdPartyLicenses"
GRDB_LICENSE="$DEPENDENCY_BUILD_DIR/checkouts/GRDB.swift/LICENSE"
SPARKLE_LICENSE="$DEPENDENCY_BUILD_DIR/artifacts/sparkle/Sparkle/LICENSE"

for LICENSE_SOURCE in "$GRDB_LICENSE" "$SPARKLE_LICENSE"; do
  if [[ ! -s "$LICENSE_SOURCE" ]]; then
    echo "error: a required dependency license is missing from the build." >&2
    exit 1
  fi
done

mkdir -p "$LICENSE_RESOURCES_DIR"
cp "$GRDB_LICENSE" "$LICENSE_RESOURCES_DIR/GRDB.txt"
cp "$SPARKLE_LICENSE" "$LICENSE_RESOURCES_DIR/Sparkle.txt"
