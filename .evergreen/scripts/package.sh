#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: package.sh <target-triple> <binary-path> <output-dir>}"
binary_path="${2:?usage: package.sh <target-triple> <binary-path> <output-dir>}"
output_dir="${3:?usage: package.sh <target-triple> <binary-path> <output-dir>}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name="atlas-cli-plugin-sh"
stage_dir_name="${name}-${target}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

stage_dir="$work_dir/$stage_dir_name"
mkdir -p "$stage_dir"

if [[ "$target" == *windows* ]]; then
  binary_name="${name}.exe"
else
  binary_name="$name"
fi

cp "$binary_path" "$stage_dir/$binary_name"
cp "$repo_root/manifest.yml" "$stage_dir/manifest.yml"
cp "$repo_root/README.md" "$stage_dir/README.md"
cp "$repo_root/LICENSE" "$stage_dir/LICENSE"

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

if [[ "$target" == *windows* ]]; then
  archive_name="${name}-${target}.zip"
  (cd "$work_dir" && zip -rq "$output_dir/$archive_name" "$stage_dir_name")
else
  archive_name="${name}-${target}.tar.gz"
  tar -czf "$output_dir/$archive_name" -C "$work_dir" "$stage_dir_name"
fi

(cd "$output_dir" && shasum -a 256 "$archive_name" >> checksums.sha256)

echo "packaged $output_dir/$archive_name"
