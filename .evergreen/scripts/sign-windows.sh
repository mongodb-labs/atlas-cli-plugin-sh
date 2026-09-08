#!/usr/bin/env bash
set -Eeuo pipefail

: "${GRS_USERNAME:?GRS_USERNAME is required}"
: "${GRS_PASSWORD:?GRS_PASSWORD is required}"
: "${AUTHENTICODE_KEY_NAME:?AUTHENTICODE_KEY_NAME is required}"
artifact="${1:?usage: sign-windows.sh <executable>}"

# Paste artifacts (trailing newline/space, CRLF) in the project expansions are a classic cause of
# "Authentication failed for user" from Garasign. Strip them loudly instead of passing a mangled value.
trim() {
  local value="${1//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}
username="$(trim "$GRS_USERNAME")"
password="$(trim "$GRS_PASSWORD")"
key_name="$(trim "$AUTHENTICODE_KEY_NAME")"
if [[ "$GRS_USERNAME" != "$username" || "$GRS_PASSWORD" != "$password" || "$AUTHENTICODE_KEY_NAME" != "$key_name" ]]; then
  echo "WARNING: whitespace trimmed from Garasign credentials; fix the garasign_username/garasign_password/authenticode_key_name expansions" >&2
  GRS_USERNAME="$username"
  GRS_PASSWORD="$password"
  AUTHENTICODE_KEY_NAME="$key_name"
fi

[[ -f "$artifact" ]] || { echo "ERROR: $artifact does not exist" >&2; exit 1; }

artifact_size="$(wc -c <"$artifact" | tr -d ' ')"
artifact_sha256="$(sha256sum "$artifact" | cut -d ' ' -f1)"

runtime=""
for candidate in docker podman; do
  if command -v "$candidate" >/dev/null 2>&1; then
    runtime="$candidate"
    break
  fi
done
[[ -n "$runtime" ]] || { echo "ERROR: docker or podman is required" >&2; exit 1; }

alias_fingerprint="$(printf '%s' "$AUTHENTICODE_KEY_NAME" | sha256sum | cut -c1-16)"
garasign_username_fingerprint="$(printf '%s' "$GRS_USERNAME" | sha256sum | cut -c1-16)"
export GRS_CONFIG_USER1_USERNAME="$GRS_USERNAME"
export GRS_CONFIG_USER1_PASSWORD="$GRS_PASSWORD"
echo "Signing artifact: size=${artifact_size} sha256=${artifact_sha256} runtime=${runtime}"
echo "Authenticode alias fingerprint: ${alias_fingerprint} length=${#AUTHENTICODE_KEY_NAME}"
echo "Garasign username fingerprint: ${garasign_username_fingerprint} password_length=${#GRS_PASSWORD}"

for attempt in 1 2 3; do
  if "$runtime" run \
    -e GRS_CONFIG_USER1_USERNAME \
    -e GRS_CONFIG_USER1_PASSWORD \
    --rm \
    -v "$(pwd):$(pwd)" \
    -w "$(pwd)" \
    901841024863.dkr.ecr.us-east-1.amazonaws.com/release-infrastructure/garasign-jsign \
    /bin/bash -c \
    'java -version; jsign --debug --tsaurl http://timestamp.digicert.com -a "$2" --replace -d SHA-256 "$1"' \
    _ "$artifact" "$AUTHENTICODE_KEY_NAME"; then
    exit 0
  fi
  [[ "$attempt" -lt 3 ]] && sleep 30
done

echo "ERROR: Windows signing failed after 3 attempts" >&2
echo "    If Garasign reported 'Authentication failed for user', the garasign_username/garasign_password" >&2
echo "    project expansions do not authenticate with the signing service. Verify the values against" >&2
echo "    the credentials issued in DEVPROD-41923 (or your DevProd signing request)." >&2
exit 1
