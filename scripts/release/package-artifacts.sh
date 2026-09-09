#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.3}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/release/$RELEASE_VERSION}"
APP_PATH="${APP_PATH:-$OUTPUT_DIR/MyMacX.app}"
ARTIFACT_BASENAME="MyMacX-$RELEASE_VERSION"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.zip"
CHECKSUM_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.sha256"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mymacx-release.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

validate_release_version "$RELEASE_VERSION"
[[ -d "$APP_PATH" ]] || die "application not found: $APP_PATH"
assert_new_path "$DMG_PATH"
assert_new_path "$ZIP_PATH"
assert_new_path "$CHECKSUM_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto "$APP_PATH" "$STAGING_DIR/MyMacX.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -fs HFS+ -volname "My Mac X $RELEASE_VERSION" \
  -srcfolder "$STAGING_DIR" -format UDZO "$DMG_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

{
  echo "$(sha256_file "$DMG_PATH")  $(basename "$DMG_PATH")"
  echo "$(sha256_file "$ZIP_PATH")  $(basename "$ZIP_PATH")"
} >"$CHECKSUM_PATH"

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
