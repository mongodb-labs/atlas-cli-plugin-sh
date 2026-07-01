#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
port=8712
trap 'kill "${server_pid:-0}" 2>/dev/null; rm -rf "$tmp_root"' EXIT

serve_dir="$tmp_root/serve"
mkdir -p "$serve_dir/linux_amd64"
echo "fake macnotary binary" > "$serve_dir/linux_amd64/macnotary"
(cd "$serve_dir" && zip -q -r macos-notary.zip linux_amd64)

python3 -m http.server "$port" --directory "$serve_dir" >/dev/null 2>&1 &
server_pid=$!
sleep 1

dest_dir="$tmp_root/dest"
"$script_dir/install-macnotary.sh" "http://127.0.0.1:$port/macos-notary.zip" "$dest_dir"

[[ -x "$dest_dir/linux_amd64/macnotary" ]] || { echo "FAIL: macnotary binary missing or not executable"; exit 1; }

echo "PASS: install-macnotary.sh"
