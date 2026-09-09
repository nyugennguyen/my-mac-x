#!/bin/bash

set -euo pipefail

die() {
  echo "release: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" ]] || die "$name is required"
}

validate_release_version() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || \
    die "invalid RELEASE_VERSION '$value'"
}

assert_new_path() {
  [[ ! -e "$1" ]] || die "refusing to overwrite immutable release output: $1"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}
