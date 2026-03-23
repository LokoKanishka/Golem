#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_NAME="openclaw-gateway.service"
WAIT_SECONDS="${GOLEM_LAUNCH_WAIT_SECONDS:-3}"
WORK_URL="${GOLEM_WORK_URL:-https://www.wikipedia.org/}"
STACK_WAIT_SECONDS="${GOLEM_STACK_WAIT_SECONDS:-2}"

require_command() {
  local cmd="$1"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: falta el comando requerido: %s\n' "$cmd" >&2
    exit 1
  fi
}

extract_dashboard_url() {
  local dashboard_raw
  local dashboard_url

  dashboard_raw="$(openclaw dashboard --no-open 2>&1)"
  dashboard_url="$(printf '%s\n' "$dashboard_raw" | sed -n 's/^Dashboard URL: //p' | tail -n 1)"

  if [ -z "$dashboard_url" ]; then
    printf 'ERROR: no se pudo resolver la URL del dashboard.\n' >&2
    printf '%s\n' "$dashboard_raw" >&2
    exit 1
  fi

  printf '%s\n' "$dashboard_url"
}

ensure_gateway_active() {
  local state
  local attempt

  state="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)"
  if [ "$state" != "active" ]; then
    printf 'gateway: iniciando %s\n' "$SERVICE_NAME"
    systemctl --user start "$SERVICE_NAME"
  else
    printf 'gateway: %s ya estaba activo\n' "$SERVICE_NAME"
  fi

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    state="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)"
    if [ "$state" = "active" ]; then
      return 0
    fi
    sleep 1
  done

  printf 'ERROR: %s no quedó activo a tiempo.\n' "$SERVICE_NAME" >&2
  exit 1
}

ensure_local_task_stack_active() {
  local attempt

  printf 'stack_local: iniciando task api + bridge\n'
  "${REPO_ROOT}/scripts/golem_host_stack_ctl.sh" start

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if "${REPO_ROOT}/scripts/golem_host_stack_ctl.sh" healthcheck >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  printf 'ERROR: el stack local task api + bridge no quedó sano a tiempo.\n' >&2
  exit 1
}

main() {
  local dashboard_url
  local self_check_output
  local self_check_status
  local launch_summary

  require_command openclaw
  require_command systemctl
  require_command google-chrome
  require_command code
  require_command python3

  cd "$REPO_ROOT"

  ensure_gateway_active
  sleep "$WAIT_SECONDS"
  ensure_local_task_stack_active
  sleep "$STACK_WAIT_SECONDS"

  dashboard_url="$(extract_dashboard_url)"

  google-chrome --new-window "$dashboard_url" "$WORK_URL" >/dev/null 2>&1 &
  code "$REPO_ROOT" >/dev/null 2>&1 &

  self_check_output="$(./scripts/self_check.sh 2>&1 || true)"
  printf '%s\n' "$self_check_output"

  self_check_status="$(printf '%s\n' "$self_check_output" | sed -n 's/^estado_general: //p' | tail -n 1)"
  if [ -z "$self_check_status" ]; then
    self_check_status="UNKNOWN"
  fi

  launch_summary="SUMMARY GOLEM"
  printf '%s\n' "$launch_summary"
  printf 'repo: %s\n' "$REPO_ROOT"
  printf 'gateway_service: active\n'
  printf 'task_stack: started\n'
  printf 'dashboard: %s\n' "$dashboard_url"
  printf 'work_tab: %s\n' "$WORK_URL"
  printf 'vscode: opened %s\n' "$REPO_ROOT"
  printf 'self_check: %s\n' "$self_check_status"
}

main "$@"
