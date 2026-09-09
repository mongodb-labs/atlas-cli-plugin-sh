#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/is-prerelease.sh"

tag="${1:-$(git tag --list 'v*' --sort=-version:refname | head -1)}"
artifacts_dir="${2:?usage: release.sh <tag> <artifacts-dir>}"
[[ -n "$tag" ]] || { echo "usage: release.sh <tag> <artifacts-dir>" >&2; exit 1; }

owner_repo="$(git remote get-url origin | sed -E 's#.*[:/]([^/]+)/([^/.]+)(\.git)?$#\1/\2#')"
[[ "$owner_repo" =~ ^[^/]+/[^/]+$ ]] || { echo "ERROR: cannot determine GitHub owner/repo from git remote" >&2; exit 1; }

prerelease=false
is_prerelease "$tag" && prerelease=true

if command -v gh >/dev/null 2>&1; then
  gh_args=(--title "$tag" --generate-notes)
  [[ "$prerelease" == true ]] && gh_args+=(--prerelease)
  gh release create "$tag" "${gh_args[@]}" "$artifacts_dir"/*
  exit 0
fi

# Publish via the GitHub API (like goreleaser) so no gh binary is needed on the host.
: "${GH_TOKEN:?GH_TOKEN is required (GitHub token for API publishing)}"
echo "gh not found; publishing ${tag} via GitHub API"
body="$(printf '{"tag_name":"%s","name":"%s","generate_release_notes":true,"prerelease":%s}' "$tag" "$tag" "$prerelease")"
release_json="$(curl -fsSL -X POST \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d "$body" \
  "https://api.github.com/repos/${owner_repo}/releases")"
release_id="$(printf '%s' "$release_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
echo "created release ${tag} (id=${release_id})"

for artifact in "$artifacts_dir"/*; do
  [[ -f "$artifact" ]] || continue
  name="$(basename "$artifact")"
  echo "uploading ${name}"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${artifact}" \
    "https://uploads.github.com/repos/${owner_repo}/releases/${release_id}/assets?name=${name}" \
    >/dev/null
done
echo "release ${tag} published"
