#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/is-prerelease.sh"

# The tag is injected as RELEASE_TAG by Evergreen at the YAML layer (see
# evergreen.yml). A ${...} reference inside this script body would be swallowed
# by Evergreen -- that is how the v1.0.0 build ended up publishing rc9 instead.
# Fall back to the manifest version so manual patches can still release.
tag="${RELEASE_TAG:-${1:-}}"
if [[ -z "$tag" ]]; then
  version="$(python3 -c "import tomllib; print(tomllib.load(open('Cargo.toml','rb'))['package']['version'])")"
  tag="v${version}"
fi
artifacts_dir="${2:?usage: release.sh <tag> <artifacts-dir>}"

owner_repo="$(git remote get-url origin | sed -E 's#.*[:/]([^/]+)/([^/.]+)(\.git)?$#\1/\2#')"
[[ "$owner_repo" =~ ^[^/]+/[^/]+$ ]] || { echo "ERROR: cannot determine GitHub owner/repo from git remote" >&2; exit 1; }

: "${GH_TOKEN:?GH_TOKEN is required (GitHub token for API publishing)}"

prerelease=false
is_prerelease "$tag" && prerelease=true

# Make releases idempotent: re-running a tag whose release already exists
# should no-op, not fail with a 422.
if curl -fsS -H "Authorization: Bearer ${GH_TOKEN}" \
  "https://api.github.com/repos/${owner_repo}/releases/tags/${tag}" >/dev/null 2>&1; then
  echo "release ${tag} already exists; skipping"
  exit 0
fi

if command -v gh >/dev/null 2>&1; then
  gh_args=(--title "$tag" --generate-notes)
  [[ "$prerelease" == true ]] && gh_args+=(--prerelease)
  gh release create "$tag" "${gh_args[@]}" "$artifacts_dir"/*
  exit 0
fi

# Publish via the GitHub API (like goreleaser) so no gh binary is needed on the host.
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
  case "$name" in
    *.tar.gz) content_type="application/x-gtar" ;;
    *.zip) content_type="application/zip" ;;
    *) content_type="application/octet-stream" ;;
  esac
  echo "uploading ${name} (${content_type})"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Content-Type: ${content_type}" \
    --data-binary "@${artifact}" \
    "https://uploads.github.com/repos/${owner_repo}/releases/${release_id}/assets?name=${name}" \
    >/dev/null
done
echo "release ${tag} published"
