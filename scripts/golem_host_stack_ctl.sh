#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TASK_API_SERVICE_NAME="${GOLEM_TASK_API_SERVICE_NAME:-golem-task-panel-http.service}"
TASK_API_SERVICE_UNIT_PATH="${GOLEM_TASK_API_SERVICE_UNIT_PATH:-$HOME/.config/systemd/user/${TASK_API_SERVICE_NAME}}"
TASK_API_HOST="${GOLEM_TASK_API_HOST:-127.0.0.1}"
TASK_API_PORT="${GOLEM_TASK_API_PORT:-8765}"

WHATSAPP_BRIDGE_SERVICE_NAME="${GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME:-golem-whatsapp-bridge.service}"
WHATSAPP_BRIDGE_SERVICE_UNIT_PATH="${GOLEM_WHATSAPP_BRIDGE_SERVICE_UNIT_PATH:-$HOME/.config/systemd/user/${WHATSAPP_BRIDGE_SERVICE_NAME}}"
WHATSAPP_BRIDGE_BASE_URL="${GOLEM_WHATSAPP_BRIDGE_BASE_URL:-http://${TASK_API_HOST}:${TASK_API_PORT}}"
WHATSAPP_BRIDGE_STATE_FILE="${GOLEM_WHATSAPP_BRIDGE_STATE_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_state.json}"
WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE="${GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_runtime.json}"
WHATSAPP_BRIDGE_AUDIT_FILE="${GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_audit.jsonl}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_stack_ctl.sh start
  ./scripts/golem_host_stack_ctl.sh stop
  ./scripts/golem_host_stack_ctl.sh restart
  ./scripts/golem_host_stack_ctl.sh status
  ./scripts/golem_host_stack_ctl.sh healthcheck
  ./scripts/golem_host_stack_ctl.sh diagnose

Env overrides:
  GOLEM_TASK_API_SERVICE_NAME
  GOLEM_TASK_API_SERVICE_UNIT_PATH
  GOLEM_TASK_API_HOST
  GOLEM_TASK_API_PORT
  GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME
  GOLEM_WHATSAPP_BRIDGE_SERVICE_UNIT_PATH
  GOLEM_WHATSAPP_BRIDGE_BASE_URL
  GOLEM_WHATSAPP_BRIDGE_STATE_FILE
  GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE
  GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE
EOF
}

run_task_api_ctl() {
  python3 "${REPO_ROOT}/scripts/task_panel_http_ctl.py" "$@" \
    --service \
    --service-name "${TASK_API_SERVICE_NAME}" \
    --service-unit-path "${TASK_API_SERVICE_UNIT_PATH}" \
    --host "${TASK_API_HOST}" \
    --port "${TASK_API_PORT}"
}

run_bridge_ctl() {
  python3 "${REPO_ROOT}/scripts/task_whatsapp_bridge_ctl.py" "$@" \
    --service \
    --service-name "${WHATSAPP_BRIDGE_SERVICE_NAME}" \
    --service-unit-path "${WHATSAPP_BRIDGE_SERVICE_UNIT_PATH}" \
    --base-url "${WHATSAPP_BRIDGE_BASE_URL}" \
    --state-file "${WHATSAPP_BRIDGE_STATE_FILE}" \
    --runtime-status-file "${WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE}" \
    --audit-file "${WHATSAPP_BRIDGE_AUDIT_FILE}"
}

command_start() {
  run_task_api_ctl start >/dev/null
  if ! run_bridge_ctl start >/dev/null; then
    run_task_api_ctl stop >/dev/null 2>&1 || true
    return 1
  fi
  command_healthcheck >/dev/null
  printf 'GOLEM_HOST_STACK_STARTED task_api=%s bridge=%s base_url=%s\n' \
    "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}" "${WHATSAPP_BRIDGE_BASE_URL}"
}

command_stop() {
  local exit_code=0

  if ! run_bridge_ctl stop >/dev/null; then
    exit_code=1
  fi
  if ! run_task_api_ctl stop >/dev/null; then
    exit_code=1
  fi

  printf 'GOLEM_HOST_STACK_STOPPED task_api=%s bridge=%s\n' \
    "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}"
  return "${exit_code}"
}

command_restart() {
  run_task_api_ctl restart >/dev/null
  run_bridge_ctl restart >/dev/null
  run_bridge_ctl healthcheck >/dev/null
  run_task_api_ctl healthcheck >/dev/null
  printf 'GOLEM_HOST_STACK_RESTARTED task_api=%s bridge=%s\n' \
    "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}"
}

command_status() {
  printf 'GOLEM HOST STACK STATUS\n'
  printf 'task_api_service: %s\n' "${TASK_API_SERVICE_NAME}"
  run_task_api_ctl status
  printf '\n'
  printf 'whatsapp_bridge_service: %s\n' "${WHATSAPP_BRIDGE_SERVICE_NAME}"
  run_bridge_ctl status
}

command_healthcheck() {
  run_task_api_ctl healthcheck >/dev/null
  run_bridge_ctl healthcheck >/dev/null
  printf 'GOLEM_HOST_STACK_HEALTHCHECK_OK task_api=%s bridge=%s\n' \
    "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}"
}

command_diagnose() {
  "${REPO_ROOT}/scripts/golem_host_diagnose.sh" snapshot
}

main() {
  if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
  fi

  cd "${REPO_ROOT}"

  case "$1" in
    start)
      command_start
      ;;
    stop)
      command_stop
      ;;
    restart)
      command_restart
      ;;
    status)
      command_status
      ;;
    healthcheck)
      command_healthcheck
      ;;
    diagnose)
      command_diagnose
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
