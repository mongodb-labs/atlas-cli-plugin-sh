#!/usr/bin/env bash
set -Eeou pipefail

ecr_registry="${ECR_REGISTRY:-901841024863.dkr.ecr.us-east-1.amazonaws.com}"
ecr_region="${ECR_REGION:-us-east-1}"
password="$(aws ecr get-login-password --region "$ecr_region")"

docker_config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
mkdir -p "$(dirname "$docker_config")"
if [[ ! -f "$docker_config" ]]; then
  printf '{}\n' >"$docker_config"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$docker_config" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as file:
    config = json.load(file)
config.pop("credsStore", None)
config.pop("credHelpers", None)
with open(path, "w") as file:
    json.dump(config, file)
PY
fi

logged_in=false
for runtime in docker podman; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  echo "Authenticating $runtime to $ecr_registry"
  if printf '%s' "$password" | "$runtime" login --username AWS --password-stdin "$ecr_registry"; then
    logged_in=true
    continue
  fi
  if [[ "$runtime" != docker ]]; then
    echo "$runtime login failed; skipping it"
    continue
  fi
  command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required for Docker credential fallback" >&2; exit 1; }
  echo "Docker login failed to store credentials; writing auth config"
  ECR_REGISTRY="$ecr_registry" ECR_PASSWORD="$password" python3 - "$docker_config" <<'PY'
import base64
import json
import os
import sys

path = sys.argv[1]
with open(path) as file:
    config = json.load(file)
auth = base64.b64encode(f"AWS:{os.environ['ECR_PASSWORD']}".encode()).decode()
config.setdefault("auths", {})[os.environ["ECR_REGISTRY"]] = {"auth": auth}
with open(path, "w") as file:
    json.dump(config, file)
PY
  chmod 600 "$docker_config"
  logged_in=true
done

[[ "$logged_in" == true ]] || { echo "ERROR: no container runtime authenticated to $ecr_registry" >&2; exit 1; }
