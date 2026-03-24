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

run_auto_diagnose() {
  local reason="$1"
  local diagnose_output snapshot_path snapshot_summary snapshot_manifest timestamp_utc
  local gateway_context gateway_last_signal suggested_first_action
  local summary_field_cmd='
    BEGIN { value = "" }
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ ("^" key ": ")) {
          sub("^" key ": ", "", $i)
          value = $i
        }
      }
    }
    END {
      if (value != "") {
        print value
      }
    }
  '

  diagnose_output="$(
    GOLEM_HOST_DIAG_TRIGGER_SOURCE="launch_golem" \
    GOLEM_HOST_DIAG_TRIGGER_REASON="$reason" \
    "${REPO_ROOT}/scripts/golem_host_diagnose.sh" auto \
    --source "launch_golem" \
    --reason "$reason" 2>&1 || true
  )"
  printf '%s\n' "$diagnose_output" | sed -n '/^GOLEM_HOST_DIAGNOSE_/p'

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
    gateway_context="$(awk -F ' \\| ' -v key='gateway_context' "$summary_field_cmd" "$snapshot_summary" | tail -n 1)"
    gateway_last_signal="$(awk -F ' \\| ' -v key='gateway_last_signal' "$summary_field_cmd" "$snapshot_summary" | tail -n 1)"
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

  printf 'GOLEM HOST FAILURE SUMMARY\n'
  printf 'reason: %s\n' "$reason"
  printf 'services: task_api=%s whatsapp_bridge=%s\n' \
    "${GOLEM_TASK_API_SERVICE_NAME:-golem-task-panel-http.service}" \
    "${GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME:-golem-whatsapp-bridge.service}"
  printf 'gateway_context: %s\n' "$gateway_context"
  printf 'gateway_last_signal: %s\n' "$gateway_last_signal"
  printf 'suggested_first_action: %s\n' "$suggested_first_action"
  printf 'snapshot: %s\n' "$snapshot_path"
  printf 'look_first: %s\n' "$snapshot_summary"
  printf 'look_next: %s\n' "$snapshot_manifest"
  printf 'timestamp_utc: %s\n' "$timestamp_utc"
  printf 'helper: ./scripts/golem_host_last_snapshot.sh\n'
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

gateway_reason_state() {
  local systemd_state
  local gateway_raw

  systemd_state="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)"
  if [ "$systemd_state" != "active" ]; then
    printf 'FAIL\n'
    return 0
  fi

  gateway_raw="$(openclaw gateway status 2>&1 || true)"
  if printf '%s\n' "$gateway_raw" | grep -q 'Runtime: running' && printf '%s\n' "$gateway_raw" | grep -q 'RPC probe: ok'; then
    printf 'OK\n'
  else
    printf 'FAIL\n'
  fi
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
  local gateway_reason
  local diagnose_reason="stack_startup_timeout"

  printf 'stack_local: iniciando task api + bridge\n'
  "${REPO_ROOT}/scripts/golem_host_stack_ctl.sh" start

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if GOLEM_HOST_AUTO_DIAGNOSE=0 "${REPO_ROOT}/scripts/golem_host_stack_ctl.sh" healthcheck >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  gateway_reason="$(gateway_reason_state)"
  if [ "$gateway_reason" = "FAIL" ]; then
    diagnose_reason="${diagnose_reason};gateway=FAIL"
  fi
  run_auto_diagnose "$diagnose_reason"
  printf 'ERROR: el stack local task api + bridge no quedó sano a tiempo.\n' >&2
  exit 1
}

main() {
  local dashboard_url
  local self_check_output
  local self_check_status
  local gateway_self_check
  local task_api_self_check
  local bridge_self_check
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
  gateway_self_check="$(printf '%s\n' "$self_check_output" | sed -n 's/^gateway: \([A-Z]*\).*/\1/p' | tail -n 1)"
  task_api_self_check="$(printf '%s\n' "$self_check_output" | sed -n 's/^task_api: \([A-Z]*\).*/\1/p' | tail -n 1)"
  bridge_self_check="$(printf '%s\n' "$self_check_output" | sed -n 's/^whatsapp_bridge_service: \([A-Z]*\).*/\1/p' | tail -n 1)"
  if [ -z "$gateway_self_check" ]; then
    gateway_self_check="UNKNOWN"
  fi
  if [ -z "$task_api_self_check" ]; then
    task_api_self_check="UNKNOWN"
  fi
  if [ -z "$bridge_self_check" ]; then
    bridge_self_check="UNKNOWN"
  fi

  if [ "$self_check_status" = "FAIL" ] || [ "$task_api_self_check" != "OK" ] || [ "$bridge_self_check" != "OK" ]; then
    run_auto_diagnose "self_check_status=${self_check_status};gateway=${gateway_self_check};task_api=${task_api_self_check};whatsapp_bridge_service=${bridge_self_check}"
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
