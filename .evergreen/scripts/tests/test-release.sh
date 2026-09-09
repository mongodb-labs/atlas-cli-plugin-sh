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

# No tag arg: must derive the latest v* tag from git (the release task runs on a
# git-tag-triggered version where triggered_by_git_tag may not be available).
latest="$(git tag --list 'v*' --sort=-version:refname | head -1)"
PATH="$fake_gh_dir:$PATH" "$script_dir/release.sh" "" "$artifacts_dir"
grep -q -- "$latest" "$record_file" || { echo "FAIL: expected derived tag $latest"; exit 1; }

# No gh on PATH -> publish must fall through to the GitHub API via curl.
fake_curl_dir="$tmp_root/curlbin"
mkdir -p "$fake_curl_dir"
curl_record="$tmp_root/curl-args.txt"
cat > "$fake_curl_dir/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CURL_RECORD"
if [[ "$*" == *api.github.com* && "$*" == *POST* ]]; then
  echo '{"id": 424242}'
fi
EOF
chmod +x "$fake_curl_dir/curl"

# controlled PATH without a real/`fake_gh` gh so the API path is exercised
PATH="$fake_curl_dir:/usr/bin:/bin:/usr/sbin:/sbin" CURL_RECORD="$curl_record" GH_TOKEN="tok" "$script_dir/release.sh" "v1.0.0-rc6" "$artifacts_dir"
grep -q "api.github.com/repos/" "$curl_record" || { echo "FAIL: curl create release not called"; exit 1; }
grep -q "uploads.github.com/repos/" "$curl_record" || { echo "FAIL: curl asset upload not called"; exit 1; }
grep -q -- "application/x-gtar" "$curl_record" || { echo "FAIL: expected tar.gz asset content-type application/x-gtar"; exit 1; }

echo "PASS: release.sh"
