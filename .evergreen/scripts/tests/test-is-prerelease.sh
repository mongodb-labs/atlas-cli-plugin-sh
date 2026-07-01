#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/lib/is-prerelease.sh"

if ! is_prerelease "v1.0.0-rc4"; then
  echo "FAIL: v1.0.0-rc4 should be prerelease"; exit 1
fi

if is_prerelease "v1.0.0"; then
  echo "FAIL: v1.0.0 should not be prerelease"; exit 1
fi

echo "PASS: is-prerelease.sh"
