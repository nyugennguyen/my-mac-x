#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

[[ $# -eq 3 ]] || die "usage: $0 CURRENT.app UPDATE.app ROLLBACK.app"
CURRENT_APP="$1"
UPDATE_APP="$2"
ROLLBACK_APP="$3"

for app in "$CURRENT_APP" "$UPDATE_APP" "$ROLLBACK_APP"; do
  [[ -d "$app" ]] || die "application not found: $app"
  codesign --verify --deep --strict --verbose=2 "$app"
done

bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist"; }
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"; }
team_id() { codesign -dv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}'; }

CURRENT_BUNDLE="$(bundle_id "$CURRENT_APP")"
UPDATE_BUNDLE="$(bundle_id "$UPDATE_APP")"
ROLLBACK_BUNDLE="$(bundle_id "$ROLLBACK_APP")"
[[ "$CURRENT_BUNDLE" == "$UPDATE_BUNDLE" && "$CURRENT_BUNDLE" == "$ROLLBACK_BUNDLE" ]] || \
  die "bundle identifier differs across current/update/rollback"

CURRENT_TEAM="$(team_id "$CURRENT_APP")"
UPDATE_TEAM="$(team_id "$UPDATE_APP")"
ROLLBACK_TEAM="$(team_id "$ROLLBACK_APP")"
[[ "$CURRENT_TEAM" == "$UPDATE_TEAM" && "$CURRENT_TEAM" == "$ROLLBACK_TEAM" ]] || \
  die "signing TeamIdentifier differs across current/update/rollback"

echo "bundle=$CURRENT_BUNDLE team=${CURRENT_TEAM:-adhoc} current=$(version "$CURRENT_APP") update=$(version "$UPDATE_APP") rollback=$(version "$ROLLBACK_APP")"
echo "signature continuity verified; perform the config-preservation protocol in docs/sprint-8/evidence/r8-09-manual-update-rollback.md"
