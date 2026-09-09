#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.3}"
APP_VERSION="${APP_VERSION:-${RELEASE_VERSION%%-*}}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/release/$RELEASE_VERSION}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
ARCHS_VALUE="${ARCHS:-arm64 x86_64}"

validate_release_version "$RELEASE_VERSION"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "APP_VERSION must be numeric (for example 0.1.0)"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || die "BUILD_NUMBER must be a positive integer"
[[ "$SIGNING_MODE" == "developer-id" || "$SIGNING_MODE" == "adhoc" ]] || \
  die "SIGNING_MODE must be developer-id or adhoc"
assert_new_path "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

require_command xcodebuild
xcodebuild \
  -project "$REPO_ROOT/MyMacX.xcodeproj" \
  -scheme MyMacX \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCHS_VALUE" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_SOURCE="$DERIVED_DATA/Build/Products/Release/MyMacX.app"
APP_OUTPUT="$OUTPUT_DIR/MyMacX.app"
[[ -d "$APP_SOURCE" ]] || die "built application not found: $APP_SOURCE"
ditto "$APP_SOURCE" "$APP_OUTPUT"

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  require_value DEVELOPER_ID_APPLICATION
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$REPO_ROOT/Configs/MyMacX.entitlements" \
    --sign "$DEVELOPER_ID_APPLICATION" "$APP_OUTPUT"
else
  codesign --force --deep --options runtime \
    --entitlements "$REPO_ROOT/Configs/MyMacX.entitlements" \
    --sign - "$APP_OUTPUT"
fi

codesign --verify --deep --strict --verbose=2 "$APP_OUTPUT"
codesign -d --entitlements :- "$APP_OUTPUT" >"$OUTPUT_DIR/embedded-entitlements.plist" 2>"$OUTPUT_DIR/codesign-display.txt"
echo "$APP_OUTPUT"
