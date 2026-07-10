#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
host_target="$(rustc -vV | sed -n 's/^host: //p')"

"$repo_root/.evergreen/scripts/build.sh" "$host_target"

binary_path="$repo_root/target/$host_target/release/atlas-cli-plugin-sh"
[[ -x "$binary_path" ]] || { echo "FAIL: expected executable binary at $binary_path"; exit 1; }

echo "PASS: build.sh (built $host_target)"
