#!/usr/bin/env bash
# Start compose services for profiles listed in PROFILES (.env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a && source .env && set +a

PROFILES="${PROFILES:-nginx}"
ARGS=()
IFS=',' read -ra PARTS <<< "$PROFILES"
for p in "${PARTS[@]}"; do
  p="$(echo "$p" | xargs)"
  [[ -z "$p" ]] && continue
  ARGS+=(--profile "$p")
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
  echo "PROFILES is empty" >&2
  exit 1
fi

echo "Starting profiles: ${PROFILES}"
docker compose "${ARGS[@]}" up -d "$@"
