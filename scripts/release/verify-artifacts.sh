#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.3}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/release/$RELEASE_VERSION}"
ARTIFACT_BASENAME="MyMacX-$RELEASE_VERSION"
CHECKSUM_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.sha256"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.zip"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mymacx-verify.XXXXXX")"
DMG_MOUNT="$WORK_DIR/dmg"
ZIP_EXTRACT="$WORK_DIR/zip"
mkdir -p "$DMG_MOUNT" "$ZIP_EXTRACT"
DMG_ATTACHED=0
cleanup() {
  if [[ "$DMG_ATTACHED" -eq 1 ]]; then
    hdiutil detach -quiet "$DMG_MOUNT" || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

validate_release_version "$RELEASE_VERSION"
[[ -f "$CHECKSUM_PATH" ]] || die "checksum manifest not found: $CHECKSUM_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 -c "$(basename "$CHECKSUM_PATH")")
hdiutil verify "$DMG_PATH"
unzip -t "$ZIP_PATH"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_DIR/MyMacX.app"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$DMG_MOUNT" "$DMG_PATH"
DMG_ATTACHED=1
codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT/MyMacX.app"
ditto -x -k "$ZIP_PATH" "$ZIP_EXTRACT"
codesign --verify --deep --strict --verbose=2 "$ZIP_EXTRACT/MyMacX.app"
echo "artifact verification passed"
