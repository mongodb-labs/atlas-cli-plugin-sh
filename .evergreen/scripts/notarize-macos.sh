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
signed_dir="$work_dir/signed"
mkdir -p "$signed_dir"

staged_binaries=()
for binary in "${binaries[@]}"; do
  staged_binary="$work_dir/$(basename "$(dirname "$binary")")-$(basename "$binary")"
  cp "$binary" "$staged_binary"
  staged_binaries+=("$staged_binary")
done

zip -j "$input_zip" "${staged_binaries[@]}"

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

for index in "${!binaries[@]}"; do
  staged_binary="${staged_binaries[$index]}"
  unzip -oj "$output_zip" "$(basename "$staged_binary")" -d "$signed_dir"
  mv "$signed_dir/$(basename "$staged_binary")" "${binaries[$index]}"
done
