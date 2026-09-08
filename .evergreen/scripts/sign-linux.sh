#!/usr/bin/env bash
set -Eeuo pipefail

: "${GRS_USERNAME:?GRS_USERNAME is required}"
: "${GRS_PASSWORD:?GRS_PASSWORD is required}"
(( $# > 0 )) || { echo "usage: sign-linux.sh <artifact>..." >&2; exit 1; }

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
if [[ "$GRS_USERNAME" != "$username" || "$GRS_PASSWORD" != "$password" ]]; then
  echo "WARNING: whitespace trimmed from Garasign credentials; fix the garasign_username/garasign_password expansions" >&2
  GRS_USERNAME="$username"
  GRS_PASSWORD="$password"
fi

runtime=""
for candidate in docker podman; do
  if command -v "$candidate" >/dev/null 2>&1; then
    runtime="$candidate"
    break
  fi
done
[[ -n "$runtime" ]] || { echo "ERROR: docker or podman is required" >&2; exit 1; }
image="901841024863.dkr.ecr.us-east-1.amazonaws.com/release-infrastructure/garasign-gpg"

garasign_username_fingerprint="$(printf '%s' "$GRS_USERNAME" | sha256sum | cut -c1-16)"
export GRS_CONFIG_USER1_USERNAME="$GRS_USERNAME"
export GRS_CONFIG_USER1_PASSWORD="$GRS_PASSWORD"
echo "Garasign username fingerprint: ${garasign_username_fingerprint} password_length=${#GRS_PASSWORD}"

for artifact in "$@"; do
  [[ -f "$artifact" ]] || { echo "ERROR: $artifact does not exist" >&2; exit 1; }
  signed=false
  for attempt in 1 2 3; do
    if "$runtime" run \
      -e GRS_CONFIG_USER1_USERNAME \
      -e GRS_CONFIG_USER1_PASSWORD \
      --rm \
      -v "$(pwd):$(pwd)" \
      -w "$(pwd)" \
      "$image" \
      /bin/bash -c \
      'gpgloader && gpg --yes --armor --output "${1}.sig" --detach-sign "$1"' \
      _ "$artifact"; then
      signed=true
      break
    fi
    [[ "$attempt" -lt 3 ]] && sleep 30
  done
  [[ "$signed" == true ]] || {
    echo "ERROR: Linux signing failed for ${artifact} after 3 attempts" >&2
    echo "    If Garasign reported 'Authentication failed for user', the garasign_username/garasign_password" >&2
    echo "    project expansions do not authenticate with the signing service. Verify the values against" >&2
    echo "    the credentials issued in DEVPROD-41923 (or your DevProd signing request)." >&2
    exit 1
  }
done
