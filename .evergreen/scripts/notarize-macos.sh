#!/usr/bin/env bash
set -euo pipefail

macnotary_bin="${1:?usage: notarize-macos.sh <macnotary-bin> <notary-url> <bundle-id> <binary...>}"
notary_url="${2:?usage: notarize-macos.sh <macnotary-bin> <notary-url> <bundle-id> <binary...>}"
bundle_id="${3:?usage: notarize-macos.sh <macnotary-bin> <notary-url> <bundle-id> <binary...>}"
shift 3
binaries=("$@")

if [[ "${#binaries[@]}" -eq 0 ]]; then
  echo "ERROR: no binaries given to notarize" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

input_zip="$work_dir/mac-bins.zip"
output_zip="$work_dir/mac-bins-signed.zip"

zip -j "$input_zip" "${binaries[@]}"

"$macnotary_bin" \
  -f "$input_zip" \
  -m notarizeAndSign \
  -u "$notary_url" \
  -b "$bundle_id" \
  -o "$output_zip"

if [[ ! -f "$output_zip" ]]; then
  echo "ERROR: $output_zip does not exist. The macOS notarization service has not run." >&2
  exit 1
fi

for binary in "${binaries[@]}"; do
  unzip -oj "$output_zip" "$(basename "$binary")" -d "$(dirname "$binary")"
done
