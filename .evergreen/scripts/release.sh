#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/is-prerelease.sh"

tag="${1:-$(git tag --list 'v*' --sort=-version:refname | head -1)}"
artifacts_dir="${2:?usage: release.sh <tag> <artifacts-dir>}"
[[ -n "$tag" ]] || { echo "usage: release.sh <tag> <artifacts-dir>" >&2; exit 1; }

if is_prerelease "$tag"; then
  gh release create "$tag" \
    --title "$tag" \
    --generate-notes \
    --prerelease \
    "$artifacts_dir"/*
else
  gh release create "$tag" \
    --title "$tag" \
    --generate-notes \
    "$artifacts_dir"/*
fi
