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

if ! profile_has caddy; then
  echo "Baseline: every non-edge host must include profile 'caddy' in PROFILES." >&2
  exit 1
fi

if [[ -z "${CADDY_DOMAIN:-}" || "${CADDY_DOMAIN}" == "example.com" ]]; then
  echo "Set CADDY_DOMAIN in .env to the public base domain before starting Caddy." >&2
  exit 1
fi

if [[ "${BESZEL_ENABLE:-false}" == "true" ]] && ! profile_has beszel-agent; then
  echo "BESZEL_ENABLE=true but PROFILES lacks 'beszel-agent' (required on every host)." >&2
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

if profile_has mailhub; then
  if [[ -z "${MAILHUB_IMAGE:-}" ]]; then
    echo "mailhub requires MAILHUB_IMAGE in .env (Aliyun ACR or other prebuilt image)." >&2
    exit 1
  fi
  if [[ -z "${MAILHUB_QQ_EMAIL:-}" || -z "${MAILHUB_QQ_AUTH_CODE:-}" ]]; then
    echo "mailhub requires MAILHUB_QQ_EMAIL and MAILHUB_QQ_AUTH_CODE in .env." >&2
    exit 1
  fi

  mailhub_interval="${MAILHUB_INTERVAL_SECONDS:-900}"
  if [[ ! "$mailhub_interval" =~ ^[1-9][0-9]*$ ]]; then
    echo "MAILHUB_INTERVAL_SECONDS must be a positive integer." >&2
    exit 1
  fi

  caldav_count=0
  [[ -n "${MAILHUB_CALDAV_URL:-}" ]] && ((caldav_count += 1))
  [[ -n "${MAILHUB_CALDAV_USERNAME:-}" ]] && ((caldav_count += 1))
  [[ -n "${MAILHUB_CALDAV_PASSWORD:-}" ]] && ((caldav_count += 1))
  if ((caldav_count > 0 && caldav_count < 3)); then
    echo "mailhub CalDAV requires URL, username, and password together." >&2
    exit 1
  fi

  if { [[ -n "${MAILHUB_LLM_API_BASE:-}" ]] && [[ -z "${MAILHUB_LLM_API_KEY:-}" ]]; } ||
    { [[ -z "${MAILHUB_LLM_API_BASE:-}" ]] && [[ -n "${MAILHUB_LLM_API_KEY:-}" ]]; }; then
    echo "mailhub LLM requires MAILHUB_LLM_API_BASE and MAILHUB_LLM_API_KEY together." >&2
    exit 1
  fi

  if { [[ -n "${MAILHUB_BARK_SERVER_URL:-}" ]] && [[ -z "${MAILHUB_BARK_KEY:-}" ]]; } ||
    { [[ -z "${MAILHUB_BARK_SERVER_URL:-}" ]] && [[ -n "${MAILHUB_BARK_KEY:-}" ]]; }; then
    echo "mailhub Bark requires MAILHUB_BARK_SERVER_URL and MAILHUB_BARK_KEY together." >&2
    exit 1
  fi
fi

echo "Host baseline reminder: SSH, Docker, firewall (22; +80/443 for Caddy HTTPS)."
"${ROOT}/scripts/up.sh"
echo "Done. Caddy serves HTTPS subdomains under CADDY_DOMAIN=${CADDY_DOMAIN} (e.g. uptime.${CADDY_DOMAIN})."
