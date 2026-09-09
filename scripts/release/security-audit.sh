#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

if rg -n 'SkyLight|\b(CGS|SLS)[A-Z][A-Za-z0-9_]*|dlopen|dlsym|@_silgen_name' Sources MyMacX.xcodeproj Configs; then
  echo "release: private API or dynamic-symbol pattern found" >&2
  exit 1
fi
if rg -n 'URLSession|NWConnection|Network\.framework|CFNetwork|https?://' Sources; then
  echo "release: undisclosed production network path found" >&2
  exit 1
fi
if rg -n 'kAX(Title|Document|URL|Description|Help|SelectedText|Value)Attribute|NSPasteboard.*(string|data)ForType|CGWindowListCreateImage|ScreenCaptureKit' Sources; then
  echo "release: prohibited content-access pattern found" >&2
  exit 1
fi
plutil -lint Configs/MyMacX.entitlements
echo "security source policy passed"
