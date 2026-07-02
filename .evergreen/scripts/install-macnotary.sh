#!/usr/bin/env bash
set -euo pipefail

url="${1:?usage: install-macnotary.sh <notary-service-url> <dest-dir>}"
dest_dir="${2:?usage: install-macnotary.sh <notary-service-url> <dest-dir>}"

mkdir -p "$dest_dir"
curl --fail --silent --show-error "$url" --output "$dest_dir/macos-notary.zip"
unzip -u "$dest_dir/macos-notary.zip" -d "$dest_dir"
chmod 755 "$dest_dir/linux_amd64/macnotary"
