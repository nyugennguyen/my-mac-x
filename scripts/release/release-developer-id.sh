#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

RELEASE_VERSION="${RELEASE_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
DOWNLOAD_LOCATION="${DOWNLOAD_LOCATION:-}"

require_value RELEASE_VERSION
require_value BUILD_NUMBER
require_value DEVELOPER_ID_APPLICATION
require_value NOTARY_KEYCHAIN_PROFILE
require_value DOWNLOAD_LOCATION

require_single_line() {
  local name="$1" value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || \
    die "$name must contain one line only"
  LC_ALL=C grep -q '^[[:print:]]*$' <<< "$value" || \
    die "$name must contain printable characters only"
}

require_single_line RELEASE_VERSION "$RELEASE_VERSION"
require_single_line DEVELOPER_ID_APPLICATION "$DEVELOPER_ID_APPLICATION"
require_single_line NOTARY_KEYCHAIN_PROFILE "$NOTARY_KEYCHAIN_PROFILE"
require_single_line DOWNLOAD_LOCATION "$DOWNLOAD_LOCATION"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || die "BUILD_NUMBER must be a positive integer"
validate_release_version "$RELEASE_VERSION"

[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || \
  die "worktree must be clean so tests and signed output use the exact same commit"

SPDX_PATH="$REPO_ROOT/docs/release/MyMacX-$RELEASE_VERSION.spdx.json"
[[ -f "$SPDX_PATH" ]] || die "prepared SBOM is missing: $SPDX_PATH"
require_command jq
require_command rg
jq -e --arg version "$RELEASE_VERSION" \
  '.name == ("MyMacX-" + $version) and .packages[0].versionInfo == $version' \
  "$SPDX_PATH" >/dev/null || die "SBOM version does not match RELEASE_VERSION"
rg -q --fixed-strings "$RELEASE_VERSION" \
  "$REPO_ROOT/docs/release/release-notes-0.1.0-beta.md" || \
  die "release notes do not name $RELEASE_VERSION"
RELEASE_METADATA_PATH="$REPO_ROOT/docs/release/MyMacX-$RELEASE_VERSION-release-metadata.md"
assert_new_path "$RELEASE_METADATA_PATH"

echo "release: testing and auditing commit $(git -C "$REPO_ROOT" rev-parse HEAD)"
xcodebuild test -quiet -project "$REPO_ROOT/MyMacX.xcodeproj" -scheme MyMacX \
  -destination 'platform=macOS' \
  -derivedDataPath "$REPO_ROOT/build/verification/$RELEASE_VERSION"
"$SCRIPT_DIR/security-audit.sh"

RELEASE_VERSION="$RELEASE_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
  SIGNING_MODE=developer-id DEVELOPER_ID_APPLICATION="$DEVELOPER_ID_APPLICATION" \
  "$SCRIPT_DIR/build-app.sh"
RELEASE_VERSION="$RELEASE_VERSION" NOTARY_KEYCHAIN_PROFILE="$NOTARY_KEYCHAIN_PROFILE" \
  "$SCRIPT_DIR/notarize-and-staple.sh"
RELEASE_VERSION="$RELEASE_VERSION" "$SCRIPT_DIR/package-artifacts.sh"
RELEASE_VERSION="$RELEASE_VERSION" "$SCRIPT_DIR/verify-artifacts.sh"

if ! (set -o noclobber; {
  printf '# My Mac X %s release metadata\n\n' "$RELEASE_VERSION"
  printf -- '- Source commit: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
  printf -- '- Developer ID Application: %s\n' "$DEVELOPER_ID_APPLICATION"
  printf -- '- Notarization/staple/Gatekeeper: PASS\n'
  printf -- '- Download location: %s\n' "$DOWNLOAD_LOCATION"
  printf -- '- Artifact checksums:\n\n```text\n'
  sed 's/^/  /' "$REPO_ROOT/build/release/$RELEASE_VERSION/MyMacX-$RELEASE_VERSION.sha256"
  printf '```\n'
} > "$RELEASE_METADATA_PATH") 2>/dev/null; then
  die "release metadata already exists and was not overwritten: $RELEASE_METADATA_PATH"
fi

echo "release: Developer ID candidate ready at $REPO_ROOT/build/release/$RELEASE_VERSION"
echo "release: metadata written to $RELEASE_METADATA_PATH"
