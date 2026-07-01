#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/is-prerelease.sh"

tag="${1:?usage: release.sh <tag> <artifacts-dir>}"
artifacts_dir="${2:?usage: release.sh <tag> <artifacts-dir>}"

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
