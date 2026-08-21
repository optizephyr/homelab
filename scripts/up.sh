#!/usr/bin/env bash
# Start selected profiles in dependency order.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a && source .env && set +a

PROFILES="${PROFILES:-}"
if [[ -z "$PROFILES" ]]; then
  echo "PROFILES is empty" >&2
  exit 1
fi

PARTS=()
IFS=',' read -ra PARTS <<< "$PROFILES"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

for p in "${PARTS[@]}"; do
  p="$(trim "$p")"
  [[ -n "$p" ]] || continue
done

profile_has() {
  local needle="$1"
  local p
  for p in "${PARTS[@]}"; do
    p="$(trim "$p")"
    [[ "$p" == "$needle" ]] && return 0
  done
  return 1
}

failures=()

require_var() {
  local name="$1"
  local message="$2"
  if [[ -z "${!name:-}" ]]; then
    failures+=("$message")
  fi
}

print_failures() {
  local failure
  echo "Deployment paused: manual prerequisites are incomplete." >&2
  for failure in "${failures[@]}"; do
    echo "  - $failure" >&2
  done
  echo "Complete the items above, update .env if needed, then re-run ./scripts/up.sh." >&2
}

run_stage() {
  local stage="$1"
  shift
  local args=()
  local p
  for p in "$@"; do
    args+=(--profile "$p")
  done

  echo "Deploying stage '${stage}': $*"
  if ((${#UP_ARGS[@]} > 0)); then
    docker compose "${args[@]}" up -d "${UP_ARGS[@]}"
  else
    docker compose "${args[@]}" up -d
  fi
}

if ! profile_has caddy; then
  echo "Every non-edge host must include profile 'caddy'." >&2
  exit 1
fi

UP_ARGS=("$@")

# Stage 0: bring up the ingress first. It is intentionally allowed to return
# 502 for backends that are not part of the current stage yet.
run_stage foundation caddy

# Stage 1: services without runtime-generated credentials. Delayed profiles
# are excluded until their manual gates below have been completed.
CORE_PROFILES=(caddy)
for p in "${PARTS[@]}"; do
  p="$(trim "$p")"
  [[ -n "$p" ]] || continue
  case "$p" in
    caddy | beszel-agent | easytier-relay | mailhub) ;;
    *) CORE_PROFILES+=("$p") ;;
  esac
done

if profile_has radicale; then
  users_file="${ROOT}/services/radicale/config/users"
  if [[ ! -s "$users_file" ]]; then
    failures+=("Radicale requires a non-empty services/radicale/config/users htpasswd file.")
  fi
fi

if ((${#failures[@]} > 0)); then
  print_failures
  exit 2
fi

if ((${#CORE_PROFILES[@]} > 1)); then
  run_stage core "${CORE_PROFILES[@]}"
fi

# Stage 2: integrations that depend on credentials or resources produced
# after the core services are reachable.
failures=()
INTEGRATION_PROFILES=()

if profile_has beszel-agent; then
  failure_count=${#failures[@]}
  if [[ "${BESZEL_ENABLE:-false}" != "true" ]]; then
    failures+=("Set BESZEL_ENABLE=true before enabling beszel-agent.")
  fi
  require_var BESZEL_HUB_URL "Create/reach the Beszel hub, then set BESZEL_HUB_URL."
  require_var BESZEL_TOKEN "Create this host in the Beszel hub UI, then set BESZEL_TOKEN."
  if ((${#failures[@]} == failure_count)); then
    INTEGRATION_PROFILES+=(beszel-agent)
  fi
fi

if profile_has easytier-relay; then
  failure_count=${#failures[@]}
  require_var EASYTIER_NETWORK_NAME "Set EASYTIER_NETWORK_NAME for easytier-relay."
  require_var EASYTIER_NETWORK_SECRET "Set EASYTIER_NETWORK_SECRET for easytier-relay."
  if [[ "${EASYTIER_SETUP_CONFIRMED:-false}" != "true" ]]; then
    failures+=("Review EasyTier command flags and firewall ports, then set EASYTIER_SETUP_CONFIRMED=true.")
  fi
  if ((${#failures[@]} == failure_count)); then
    INTEGRATION_PROFILES+=(easytier-relay)
  fi
fi

if profile_has mailhub; then
  failure_count=${#failures[@]}
  require_var MAILHUB_IMAGE "Set MAILHUB_IMAGE to a prebuilt registry image."
  require_var MAILHUB_QQ_EMAIL "Set MAILHUB_QQ_EMAIL."
  require_var MAILHUB_QQ_AUTH_CODE "Enable QQ IMAP and set MAILHUB_QQ_AUTH_CODE."

  mailhub_interval="${MAILHUB_INTERVAL_SECONDS:-900}"
  if [[ ! "$mailhub_interval" =~ ^[1-9][0-9]*$ ]]; then
    failures+=("MAILHUB_INTERVAL_SECONDS must be a positive integer.")
  fi

  caldav_count=0
  [[ -n "${MAILHUB_CALDAV_URL:-}" ]] && ((caldav_count += 1))
  [[ -n "${MAILHUB_CALDAV_USERNAME:-}" ]] && ((caldav_count += 1))
  [[ -n "${MAILHUB_CALDAV_PASSWORD:-}" ]] && ((caldav_count += 1))
  if ((caldav_count > 0 && caldav_count < 3)); then
    failures+=("Mailhub CalDAV requires URL, username, and password together.")
  elif ((caldav_count == 3)); then
    if [[ "${MAILHUB_CALDAV_URL}" == http://radicale:* ]] && ! profile_has radicale; then
      failures+=("MAILHUB_CALDAV_URL targets radicale, but PROFILES does not include radicale.")
    fi
    if [[ "${MAILHUB_CALDAV_SETUP_CONFIRMED:-false}" != "true" ]]; then
      failures+=("Create the configured Radicale calendar/reminder collections, then set MAILHUB_CALDAV_SETUP_CONFIRMED=true.")
    fi
  fi

  if { [[ -n "${MAILHUB_LLM_API_BASE:-}" ]] && [[ -z "${MAILHUB_LLM_API_KEY:-}" ]]; } ||
    { [[ -z "${MAILHUB_LLM_API_BASE:-}" ]] && [[ -n "${MAILHUB_LLM_API_KEY:-}" ]]; }; then
    failures+=("Mailhub LLM requires MAILHUB_LLM_API_BASE and MAILHUB_LLM_API_KEY together.")
  fi

  if { [[ -n "${MAILHUB_BARK_SERVER_URL:-}" ]] && [[ -z "${MAILHUB_BARK_KEY:-}" ]]; } ||
    { [[ -z "${MAILHUB_BARK_SERVER_URL:-}" ]] && [[ -n "${MAILHUB_BARK_KEY:-}" ]]; }; then
    failures+=("Mailhub Bark requires MAILHUB_BARK_SERVER_URL and MAILHUB_BARK_KEY together.")
  elif [[ -n "${MAILHUB_BARK_SERVER_URL:-}" ]] &&
    [[ "${MAILHUB_BARK_SERVER_URL}" == http://bark-server:* ]] &&
    ! profile_has bark; then
    failures+=("MAILHUB_BARK_SERVER_URL targets bark-server, but PROFILES does not include bark.")
  fi

  if [[ "${MAILHUB_DRY_RUN_CONFIRMED:-false}" != "true" ]]; then
    failures+=("Run Mailhub list-calendars/list-reminders and sync --dry-run, review the output, then set MAILHUB_DRY_RUN_CONFIRMED=true.")
  fi
  if ((${#failures[@]} == failure_count)); then
    INTEGRATION_PROFILES+=(mailhub)
  fi
fi

if ((${#INTEGRATION_PROFILES[@]} > 0)); then
  run_stage integrations "${INTEGRATION_PROFILES[@]}"
fi

if ((${#failures[@]} > 0)); then
  print_failures
  exit 2
fi

echo "Deployment complete for PROFILES=${PROFILES}"
