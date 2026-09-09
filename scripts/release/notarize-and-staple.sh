#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.3}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/release/$RELEASE_VERSION}"
APP_PATH="${APP_PATH:-$OUTPUT_DIR/MyMacX.app}"
SUBMISSION_ZIP="$OUTPUT_DIR/MyMacX-$RELEASE_VERSION-notary.zip"

require_value NOTARY_KEYCHAIN_PROFILE
[[ -d "$APP_PATH" ]] || die "application not found: $APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
assert_new_path "$SUBMISSION_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait \
  --output-format json >"$OUTPUT_DIR/notary-result.json"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
echo "$APP_PATH"
