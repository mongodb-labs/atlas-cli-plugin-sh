#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

dummy_binary="$tmp_root/dummy-binary"
echo "fake binary contents" > "$dummy_binary"

output_dir="$tmp_root/out"

"$script_dir/package.sh" "x86_64-unknown-linux-gnu" "$dummy_binary" "$output_dir"
"$script_dir/package.sh" "x86_64-pc-windows-msvc" "$dummy_binary" "$output_dir"

archive_linux="$output_dir/atlas-cli-plugin-sh-x86_64-unknown-linux-gnu.tar.gz"
archive_windows="$output_dir/atlas-cli-plugin-sh-x86_64-pc-windows-msvc.zip"

[[ -f "$archive_linux" ]] || { echo "FAIL: missing $archive_linux"; exit 1; }
[[ -f "$archive_windows" ]] || { echo "FAIL: missing $archive_windows"; exit 1; }

tar -tzf "$archive_linux" | grep -q "atlas-cli-plugin-sh-x86_64-unknown-linux-gnu/atlas-cli-plugin-sh$" \
  || { echo "FAIL: linux archive missing binary"; exit 1; }
tar -tzf "$archive_linux" | grep -q "manifest.yml$" \
  || { echo "FAIL: linux archive missing manifest.yml"; exit 1; }

unzip -l "$archive_windows" | grep -q "atlas-cli-plugin-sh.exe$" \
  || { echo "FAIL: windows archive missing .exe binary"; exit 1; }

checksums="$output_dir/checksums.sha256"
[[ -f "$checksums" ]] || { echo "FAIL: missing checksums file"; exit 1; }
lines="$(wc -l < "$checksums" | tr -d ' ')"
[[ "$lines" == "2" ]] || { echo "FAIL: expected 2 checksum lines, got $lines"; exit 1; }

echo "PASS: package.sh"
