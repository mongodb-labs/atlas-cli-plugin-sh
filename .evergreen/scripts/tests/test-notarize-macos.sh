#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

bin1="$tmp_root/atlas-cli-plugin-sh-aarch64"
bin2="$tmp_root/atlas-cli-plugin-sh-x86_64"
echo "arm64 binary" > "$bin1"
echo "x86_64 binary" > "$bin2"

fake_ok="$tmp_root/macnotary-ok"
cat > "$fake_ok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
input=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f) input="$2"; shift 2;;
    -o) output="$2"; shift 2;;
    -m|-u|-b) shift 2;;
    *) shift;;
  esac
done
cp "$input" "$output"
EOF
chmod +x "$fake_ok"

"$script_dir/notarize-macos.sh" "$fake_ok" "https://example.invalid/api" "com.example.test" "$bin1" "$bin2"
echo "PASS: notarize-macos.sh succeeds when macnotary produces output"

fake_fail="$tmp_root/macnotary-fail"
cat > "$fake_fail" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_fail"

fail_output="$tmp_root/fail-output.txt"
if "$script_dir/notarize-macos.sh" "$fake_fail" "https://example.invalid/api" "com.example.test" "$bin1" "$bin2" 2>"$fail_output"; then
  echo "FAIL: notarize-macos.sh should have failed when macnotary produces no output"
  exit 1
fi
grep -q "has not run" "$fail_output" || { echo "FAIL: expected error message not found"; exit 1; }
echo "PASS: notarize-macos.sh fails correctly when macnotary produces no output"
