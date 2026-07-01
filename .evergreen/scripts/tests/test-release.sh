#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

artifacts_dir="$tmp_root/artifacts"
mkdir -p "$artifacts_dir"
echo "dummy" > "$artifacts_dir/atlas-cli-plugin-sh-x86_64-unknown-linux-gnu.tar.gz"

fake_gh_dir="$tmp_root/bin"
mkdir -p "$fake_gh_dir"
record_file="$tmp_root/gh-args.txt"
cat > "$fake_gh_dir/gh" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$record_file"
EOF
chmod +x "$fake_gh_dir/gh"

PATH="$fake_gh_dir:$PATH" "$script_dir/release.sh" "v1.0.0-rc4" "$artifacts_dir"
grep -q -- "--prerelease" "$record_file" || { echo "FAIL: expected --prerelease for rc tag"; exit 1; }

PATH="$fake_gh_dir:$PATH" "$script_dir/release.sh" "v1.0.0" "$artifacts_dir"
if grep -q -- "--prerelease" "$record_file"; then
  echo "FAIL: did not expect --prerelease for stable tag"; exit 1
fi

echo "PASS: release.sh"
