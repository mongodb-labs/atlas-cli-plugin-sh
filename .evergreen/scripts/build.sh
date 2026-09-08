#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: build.sh <target-triple>}"

rustup target add "$target"
cargo build --release --target "$target"

binary="target/$target/release/atlas-cli-plugin-sh"
if [[ "$target" == *windows* ]]; then
  binary+=".exe"
fi
[[ -f "$binary" ]] || { echo "ERROR: expected build output $binary does not exist" >&2; exit 1; }
