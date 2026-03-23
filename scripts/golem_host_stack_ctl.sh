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
  GOLEM_HOST_AUTO_DIAGNOSE
  GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS
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

trigger_auto_diagnose() {
  local reason="$1"
  local diagnose_output snapshot_path snapshot_summary snapshot_manifest timestamp_utc
  local gateway_context gateway_last_signal suggested_first_action

  diagnose_output="$(
    GOLEM_HOST_DIAG_TRIGGER_SOURCE="golem_host_stack_ctl" \
    GOLEM_HOST_DIAG_TRIGGER_REASON="$reason" \
    "${REPO_ROOT}/scripts/golem_host_diagnose.sh" auto \
    --source "golem_host_stack_ctl" \
    --reason "$reason" 2>&1 || true
  )"
  printf '%s\n' "$diagnose_output" | sed -n '/^GOLEM_HOST_DIAGNOSE_/p' >&2

  snapshot_path="$(printf '%s\n' "$diagnose_output" | sed -n 's/^GOLEM_HOST_DIAGNOSE_SNAPSHOT //p' | tail -n 1)"
  if [ -z "$snapshot_path" ]; then
    snapshot_path="$(GOLEM_HOST_DIAGNOSTICS_ROOT="${GOLEM_HOST_DIAGNOSTICS_ROOT:-${REPO_ROOT}/diagnostics/host}" "${REPO_ROOT}/scripts/golem_host_last_snapshot.sh" path 2>/dev/null || true)"
  fi
  if [ -z "$snapshot_path" ]; then
    snapshot_path="(none)"
  fi

  snapshot_summary="${snapshot_path}/summary.txt"
  snapshot_manifest="${snapshot_path}/manifest.json"
  timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -f "$snapshot_summary" ]; then
    timestamp_utc="$(sed -n 's/^trigger_requested_at_utc: //p' "$snapshot_summary" | tail -n 1)"
    gateway_context="$(sed -n 's/^gateway_context: //p' "$snapshot_summary" | tail -n 1)"
    gateway_last_signal="$(sed -n 's/^gateway_last_signal: //p' "$snapshot_summary" | tail -n 1)"
    suggested_first_action="$(sed -n 's/^suggested_first_action: //p' "$snapshot_summary" | tail -n 1)"
    if [ -z "$timestamp_utc" ]; then
      timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    if [ -z "$gateway_context" ]; then
      gateway_context="unavailable"
    fi
    if [ -z "$gateway_last_signal" ]; then
      gateway_last_signal="(none)"
    fi
    if [ -z "$suggested_first_action" ]; then
      suggested_first_action="mirar summary.txt del ultimo snapshot"
    fi
  else
    gateway_context="unavailable"
    gateway_last_signal="(none)"
    suggested_first_action="mirar summary.txt del ultimo snapshot"
  fi

  printf 'GOLEM HOST FAILURE SUMMARY\n' >&2
  printf 'reason: %s\n' "$reason" >&2
  printf 'services: task_api=%s whatsapp_bridge=%s\n' "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}" >&2
  printf 'gateway_context: %s\n' "$gateway_context" >&2
  printf 'gateway_last_signal: %s\n' "$gateway_last_signal" >&2
  printf 'suggested_first_action: %s\n' "$suggested_first_action" >&2
  printf 'snapshot: %s\n' "$snapshot_path" >&2
  printf 'look_first: %s\n' "$snapshot_summary" >&2
  printf 'look_next: %s\n' "$snapshot_manifest" >&2
  printf 'timestamp_utc: %s\n' "$timestamp_utc" >&2
  printf 'helper: ./scripts/golem_host_last_snapshot.sh\n' >&2
}

stack_healthcheck_raw() {
  local exit_code=0

  if ! run_task_api_ctl healthcheck >/dev/null; then
    exit_code=1
  fi
  if ! run_bridge_ctl healthcheck >/dev/null; then
    exit_code=1
  fi

  return "${exit_code}"
}

command_start() {
  if ! run_task_api_ctl start >/dev/null; then
    trigger_auto_diagnose "task_api_start_failed"
    return 1
  fi
  if ! run_bridge_ctl start >/dev/null; then
    run_task_api_ctl stop >/dev/null 2>&1 || true
    trigger_auto_diagnose "whatsapp_bridge_start_failed"
    return 1
  fi
  if ! stack_healthcheck_raw; then
    trigger_auto_diagnose "stack_healthcheck_failed_after_start"
    return 1
  fi
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
  if ! run_task_api_ctl restart >/dev/null; then
    trigger_auto_diagnose "task_api_restart_failed"
    return 1
  fi
  if ! run_bridge_ctl restart >/dev/null; then
    trigger_auto_diagnose "whatsapp_bridge_restart_failed"
    return 1
  fi
  if ! stack_healthcheck_raw; then
    trigger_auto_diagnose "stack_healthcheck_failed_after_restart"
    return 1
  fi
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
  if ! stack_healthcheck_raw; then
    trigger_auto_diagnose "stack_healthcheck_failed"
    return 1
  fi
  printf 'GOLEM_HOST_STACK_HEALTHCHECK_OK task_api=%s bridge=%s\n' \
    "${TASK_API_SERVICE_NAME}" "${WHATSAPP_BRIDGE_SERVICE_NAME}"
}

command_diagnose() {
  GOLEM_HOST_DIAG_TRIGGER_SOURCE="golem_host_stack_ctl" \
  GOLEM_HOST_DIAG_TRIGGER_REASON="manual_stack_diagnose" \
  "${REPO_ROOT}/scripts/golem_host_diagnose.sh" snapshot \
    --source "golem_host_stack_ctl" \
    --reason "manual_stack_diagnose"
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
