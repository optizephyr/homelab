#!/usr/bin/env bash
# New Ubuntu host: verify baseline, then start selected profiles.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example and fill secrets:"
  echo "  cp .env.example .env && chmod 600 .env"
  exit 1
fi

# shellcheck disable=SC1091
set -a && source .env && set +a

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install Docker Engine + Compose plugin, then re-run."
  echo "  https://docs.docker.com/engine/install/ubuntu/"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin missing (docker compose)."
  exit 1
fi

PROFILES="${PROFILES:-}"
if [[ -z "$PROFILES" ]]; then
  echo "PROFILES is empty in .env" >&2
  exit 1
fi

profile_has() {
  local needle="$1"
  local p
  local IFS=','
  # shellcheck disable=SC2086
  for p in $PROFILES; do
    p="$(echo "$p" | xargs)"
    [[ "$p" == "$needle" ]] && return 0
  done
  return 1
}

if ! profile_has nginx; then
  echo "Baseline: every non-edge host must include profile 'nginx' in PROFILES." >&2
  exit 1
fi

if [[ "${ENABLE_BESZEL:-false}" == "true" ]] && ! profile_has beszel-agent; then
  echo "ENABLE_BESZEL=true but PROFILES lacks 'beszel-agent' (required on every host)." >&2
  exit 1
fi

if profile_has radicale; then
  users_file="${ROOT}/services/radicale/config/users"
  if [[ ! -f "$users_file" ]]; then
    touch "$users_file"
    chmod 600 "$users_file"
    echo "Created empty $users_file — add htpasswd hashes before clients can log in."
    echo "  See services/radicale/README.md"
  fi
fi

echo "Host baseline reminder: SSH, Docker, firewall (22; +80/443 if public HTTP)."
"${ROOT}/scripts/up.sh"
echo "Done. Nginx subdomains use DOMAIN=${DOMAIN:-unset} (e.g. uptime.${DOMAIN:-example.com})."
