#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

artifact="$tmp_root/atlas-cli-plugin-sh"
record="$tmp_root/record"
printf 'binary\n' >"$artifact"

cat >"$tmp_root/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$SIGN_RECORD"
printf 'GRS_CONFIG_USER1_USERNAME=%s\n' "${GRS_CONFIG_USER1_USERNAME:-unset}" >>"$SIGN_RECORD"
printf 'GRS_CONFIG_USER1_PASSWORD=%s\n' "${GRS_CONFIG_USER1_PASSWORD:-unset}" >>"$SIGN_RECORD"
EOF
chmod +x "$tmp_root/docker"

PATH="$tmp_root:$PATH" \
SIGN_RECORD="$record" \
GRS_USERNAME=" user " \
GRS_PASSWORD="password " \
AUTHENTICODE_KEY_NAME=" test-key" \
  "$script_dir/sign-windows.sh" "$artifact"

PATH="$tmp_root:$PATH" \
SIGN_RECORD="$record" \
GRS_USERNAME="user " \
GRS_PASSWORD=$' password\r' \
  "$script_dir/sign-linux.sh" "$artifact"

record_content="$(<"$record")"
[[ "$record_content" == *"garasign-jsign"* ]] || { echo "FAIL: jsign image not used"; exit 1; }
[[ "$record_content" == *"garasign-gpg"* ]] || { echo "FAIL: gpg image not used"; exit 1; }
[[ "$record_content" == *"GRS_CONFIG_USER1_USERNAME=user"* ]] || { echo "FAIL: Garasign username not passed"; exit 1; }
[[ "$record_content" == *"GRS_CONFIG_USER1_PASSWORD=password"* ]] || { echo "FAIL: Garasign password not passed"; exit 1; }
[[ "$record_content" == *"test-key"* ]] || { echo "FAIL: Authenticode key not passed"; exit 1; }
[[ "$record_content" == *"--debug"* ]] || { echo "FAIL: jsign debug mode not enabled"; exit 1; }
[[ "$record_content" != *"GRS_CONFIG_USER1_USERNAME=user "* ]] || { echo "FAIL: username trailing space not trimmed"; exit 1; }
[[ "$record_content" != *"GRS_CONFIG_USER1_PASSWORD=password "* ]] || { echo "FAIL: password trailing space not trimmed"; exit 1; }
echo "PASS: signing commands"
