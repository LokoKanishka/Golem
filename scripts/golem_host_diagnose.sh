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

DIAGNOSTICS_ROOT="${GOLEM_HOST_DIAGNOSTICS_ROOT:-${REPO_ROOT}/diagnostics/host}"
JOURNAL_LINES="${GOLEM_HOST_DIAG_JOURNAL_LINES:-80}"
AUTO_DIAG_STATE_FILE="${GOLEM_HOST_AUTO_DIAGNOSE_STATE_FILE:-${REPO_ROOT}/state/tmp/golem_host_diagnose_auto_state.json}"
AUTO_DIAG_COOLDOWN_SECONDS="${GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS:-30}"

LAST_SNAPSHOT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_diagnose.sh
  ./scripts/golem_host_diagnose.sh snapshot [--source <source>] [--reason <reason>]
  ./scripts/golem_host_diagnose.sh auto --source <source> --reason <reason>

Env overrides:
  GOLEM_HOST_DIAGNOSTICS_ROOT
  GOLEM_HOST_DIAG_JOURNAL_LINES
  GOLEM_HOST_AUTO_DIAGNOSE
  GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS
  GOLEM_HOST_AUTO_DIAGNOSE_STATE_FILE
  GOLEM_HOST_DIAG_DISABLE_AUTO
  GOLEM_HOST_DIAG_TRIGGER_SOURCE
  GOLEM_HOST_DIAG_TRIGGER_REASON
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

env_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
  esac
  return 1
}

capture_split() {
  local stdout_path="$1"
  local stderr_path="$2"
  local exit_path="$3"
  shift 3

  set +e
  "$@" >"$stdout_path" 2>"$stderr_path"
  local exit_code=$?
  set -e

  printf '%s\n' "$exit_code" >"$exit_path"
}

write_text() {
  local target="$1"
  shift
  printf '%s\n' "$@" >"$target"
}

sanitize_reason() {
  local raw="${1:-}"
  raw="${raw//$'\n'/ }"
  raw="${raw//$'\r'/ }"
  printf '%s\n' "$raw"
}

read_auto_state() {
  python3 - "$AUTO_DIAG_STATE_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    print("\t\t\t")
    raise SystemExit(0)

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("\t\t\t")
    raise SystemExit(0)

if not isinstance(payload, dict):
    print("\t\t\t")
    raise SystemExit(0)

epoch = payload.get("last_trigger_epoch", "")
source = str(payload.get("source", ""))
reason = str(payload.get("reason", ""))
snapshot = str(payload.get("snapshot_dir", ""))
print(f"{epoch}\t{source}\t{reason}\t{snapshot}")
PY
}

write_auto_state() {
  local trigger_source="$1"
  local trigger_reason="$2"
  local snapshot_dir="$3"
  local trigger_epoch="$4"

  mkdir -p "$(dirname "$AUTO_DIAG_STATE_FILE")"

  python3 - "$AUTO_DIAG_STATE_FILE" "$trigger_source" "$trigger_reason" "$snapshot_dir" "$trigger_epoch" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = {
    "source": sys.argv[2],
    "reason": sys.argv[3],
    "snapshot_dir": sys.argv[4],
    "last_trigger_epoch": int(sys.argv[5]),
}
path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY
}

perform_snapshot() {
  local trigger_mode="$1"
  local trigger_source="$2"
  local trigger_reason="$3"
  local snapshot_ts snapshot_dir trigger_requested_at

  cd "$REPO_ROOT"

  snapshot_ts="$(date -u +%Y%m%dT%H%M%SZ)"
  trigger_requested_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  snapshot_dir="${DIAGNOSTICS_ROOT}/${snapshot_ts}-golem-host-diagnose"
  mkdir -p "$snapshot_dir"

  trigger_reason="$(sanitize_reason "$trigger_reason")"

  write_text "${snapshot_dir}/meta.env" \
    "snapshot_timestamp_utc=${snapshot_ts}" \
    "repo_root=${REPO_ROOT}" \
    "user=$(id -un)" \
    "hostname=$(hostname)" \
    "trigger_mode=${trigger_mode}" \
    "trigger_source=${trigger_source}" \
    "trigger_reason=${trigger_reason}" \
    "trigger_requested_at_utc=${trigger_requested_at}" \
    "auto_cooldown_seconds=${AUTO_DIAG_COOLDOWN_SECONDS}" \
    "task_api_service_name=${TASK_API_SERVICE_NAME}" \
    "task_api_service_unit_path=${TASK_API_SERVICE_UNIT_PATH}" \
    "task_api_host=${TASK_API_HOST}" \
    "task_api_port=${TASK_API_PORT}" \
    "whatsapp_bridge_service_name=${WHATSAPP_BRIDGE_SERVICE_NAME}" \
    "whatsapp_bridge_service_unit_path=${WHATSAPP_BRIDGE_SERVICE_UNIT_PATH}" \
    "whatsapp_bridge_base_url=${WHATSAPP_BRIDGE_BASE_URL}" \
    "whatsapp_bridge_state_file=${WHATSAPP_BRIDGE_STATE_FILE}" \
    "whatsapp_bridge_runtime_status_file=${WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE}" \
    "whatsapp_bridge_audit_file=${WHATSAPP_BRIDGE_AUDIT_FILE}" \
    "journal_lines=${JOURNAL_LINES}"

  capture_split \
    "${snapshot_dir}/stack_status.txt" \
    "${snapshot_dir}/stack_status.stderr.txt" \
    "${snapshot_dir}/stack_status.exit_code" \
    ./scripts/golem_host_stack_ctl.sh status

  capture_split \
    "${snapshot_dir}/stack_healthcheck.txt" \
    "${snapshot_dir}/stack_healthcheck.stderr.txt" \
    "${snapshot_dir}/stack_healthcheck.exit_code" \
    env GOLEM_HOST_AUTO_DIAGNOSE=0 GOLEM_HOST_DIAG_DISABLE_AUTO=1 ./scripts/golem_host_stack_ctl.sh healthcheck

  capture_split \
    "${snapshot_dir}/task_api_status.json" \
    "${snapshot_dir}/task_api_status.stderr.txt" \
    "${snapshot_dir}/task_api_status.exit_code" \
    python3 ./scripts/task_panel_http_ctl.py status \
      --service \
      --service-name "$TASK_API_SERVICE_NAME" \
      --service-unit-path "$TASK_API_SERVICE_UNIT_PATH" \
      --host "$TASK_API_HOST" \
      --port "$TASK_API_PORT" \
      --json

  capture_split \
    "${snapshot_dir}/task_api_healthcheck.json" \
    "${snapshot_dir}/task_api_healthcheck.stderr.txt" \
    "${snapshot_dir}/task_api_healthcheck.exit_code" \
    python3 ./scripts/task_panel_http_ctl.py healthcheck \
      --service \
      --service-name "$TASK_API_SERVICE_NAME" \
      --service-unit-path "$TASK_API_SERVICE_UNIT_PATH" \
      --host "$TASK_API_HOST" \
      --port "$TASK_API_PORT" \
      --json

  capture_split \
    "${snapshot_dir}/whatsapp_bridge_status.json" \
    "${snapshot_dir}/whatsapp_bridge_status.stderr.txt" \
    "${snapshot_dir}/whatsapp_bridge_status.exit_code" \
    python3 ./scripts/task_whatsapp_bridge_ctl.py status \
      --service \
      --service-name "$WHATSAPP_BRIDGE_SERVICE_NAME" \
      --service-unit-path "$WHATSAPP_BRIDGE_SERVICE_UNIT_PATH" \
      --base-url "$WHATSAPP_BRIDGE_BASE_URL" \
      --state-file "$WHATSAPP_BRIDGE_STATE_FILE" \
      --runtime-status-file "$WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE" \
      --audit-file "$WHATSAPP_BRIDGE_AUDIT_FILE" \
      --json

  capture_split \
    "${snapshot_dir}/whatsapp_bridge_healthcheck.json" \
    "${snapshot_dir}/whatsapp_bridge_healthcheck.stderr.txt" \
    "${snapshot_dir}/whatsapp_bridge_healthcheck.exit_code" \
    python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
      --service \
      --service-name "$WHATSAPP_BRIDGE_SERVICE_NAME" \
      --service-unit-path "$WHATSAPP_BRIDGE_SERVICE_UNIT_PATH" \
      --base-url "$WHATSAPP_BRIDGE_BASE_URL" \
      --state-file "$WHATSAPP_BRIDGE_STATE_FILE" \
      --runtime-status-file "$WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE" \
      --audit-file "$WHATSAPP_BRIDGE_AUDIT_FILE" \
      --json

  capture_split \
    "${snapshot_dir}/systemctl_task_api_show.txt" \
    "${snapshot_dir}/systemctl_task_api_show.stderr.txt" \
    "${snapshot_dir}/systemctl_task_api_show.exit_code" \
    systemctl --user show "$TASK_API_SERVICE_NAME" \
      --property Id,LoadState,ActiveState,SubState,MainPID,UnitFileState,FragmentPath,Result,ExecMainStatus \
      --no-page

  capture_split \
    "${snapshot_dir}/systemctl_bridge_show.txt" \
    "${snapshot_dir}/systemctl_bridge_show.stderr.txt" \
    "${snapshot_dir}/systemctl_bridge_show.exit_code" \
    systemctl --user show "$WHATSAPP_BRIDGE_SERVICE_NAME" \
      --property Id,LoadState,ActiveState,SubState,MainPID,UnitFileState,FragmentPath,Result,ExecMainStatus \
      --no-page

  capture_split \
    "${snapshot_dir}/systemctl_task_api_status.txt" \
    "${snapshot_dir}/systemctl_task_api_status.stderr.txt" \
    "${snapshot_dir}/systemctl_task_api_status.exit_code" \
    systemctl --user status "$TASK_API_SERVICE_NAME" --no-pager --full

  capture_split \
    "${snapshot_dir}/systemctl_bridge_status.txt" \
    "${snapshot_dir}/systemctl_bridge_status.stderr.txt" \
    "${snapshot_dir}/systemctl_bridge_status.exit_code" \
    systemctl --user status "$WHATSAPP_BRIDGE_SERVICE_NAME" --no-pager --full

  capture_split \
    "${snapshot_dir}/journal_task_api_tail.txt" \
    "${snapshot_dir}/journal_task_api_tail.stderr.txt" \
    "${snapshot_dir}/journal_task_api_tail.exit_code" \
    journalctl --user -u "$TASK_API_SERVICE_NAME" --no-pager --output short-iso -n "$JOURNAL_LINES"

  capture_split \
    "${snapshot_dir}/journal_bridge_tail.txt" \
    "${snapshot_dir}/journal_bridge_tail.stderr.txt" \
    "${snapshot_dir}/journal_bridge_tail.exit_code" \
    journalctl --user -u "$WHATSAPP_BRIDGE_SERVICE_NAME" --no-pager --output short-iso -n "$JOURNAL_LINES"

  if command -v openclaw >/dev/null 2>&1; then
    capture_split \
      "${snapshot_dir}/gateway_status.txt" \
      "${snapshot_dir}/gateway_status.stderr.txt" \
      "${snapshot_dir}/gateway_status.exit_code" \
      openclaw gateway status
  else
    write_text "${snapshot_dir}/gateway_status.txt" "openclaw command not available"
    write_text "${snapshot_dir}/gateway_status.stderr.txt" ""
    write_text "${snapshot_dir}/gateway_status.exit_code" "127"
  fi

  capture_split \
    "${snapshot_dir}/gateway_systemd_state.txt" \
    "${snapshot_dir}/gateway_systemd_state.stderr.txt" \
    "${snapshot_dir}/gateway_systemd_state.exit_code" \
    systemctl --user is-active openclaw-gateway.service

  capture_split \
    "${snapshot_dir}/process_table.txt" \
    "${snapshot_dir}/process_table.stderr.txt" \
    "${snapshot_dir}/process_table.exit_code" \
    ps -eo pid,ppid,pgid,etime,stat,cmd --sort=pid

  capture_split \
    "${snapshot_dir}/ports_listening.txt" \
    "${snapshot_dir}/ports_listening.stderr.txt" \
    "${snapshot_dir}/ports_listening.exit_code" \
    ss -ltnp

  python3 - "$snapshot_dir" "$TASK_API_PORT" "$trigger_mode" "$trigger_source" "$trigger_reason" "$trigger_requested_at" "$AUTO_DIAG_COOLDOWN_SECONDS" <<'PY'
import json
import pathlib
import sys
from typing import Any

snapshot_dir = pathlib.Path(sys.argv[1])
task_api_port = sys.argv[2]
trigger_mode = sys.argv[3]
trigger_source = sys.argv[4]
trigger_reason = sys.argv[5]
trigger_requested_at = sys.argv[6]
auto_cooldown_seconds = sys.argv[7]


def read_text(name: str) -> str:
    path = snapshot_dir / name
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def read_json(name: str) -> dict[str, Any]:
    raw = read_text(name)
    if not raw.strip():
        return {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def read_exit(name: str) -> int:
    raw = read_text(name).strip()
    try:
        return int(raw)
    except ValueError:
        return 1


def read_props(name: str) -> dict[str, str]:
    props: dict[str, str] = {}
    for line in read_text(name).splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props[key] = value
    return props


def extract_failure(status_payload: dict[str, Any], health_payload: dict[str, Any], props: dict[str, str], journal_text: str) -> str:
    reasons = health_payload.get("reasons")
    if isinstance(reasons, list) and reasons:
        return ",".join(str(item) for item in reasons)
    runtime = status_payload.get("runtime")
    if isinstance(runtime, dict):
        last_error = runtime.get("last_error")
        if isinstance(last_error, str) and last_error.strip():
            return last_error.strip()
    result = props.get("Result", "")
    if result and result not in {"success", "done"}:
        return f"systemd_result={result}"
    exec_status = props.get("ExecMainStatus", "")
    if exec_status and exec_status not in {"0", ""}:
        return f"exec_main_status={exec_status}"
    for line in reversed(journal_text.splitlines()):
        lowered = line.lower()
        if any(token in lowered for token in (" fail", "error", "traceback", "exception", "fatal")):
            return line.strip()
    return "none"


def suggest_first_action(
    trigger_reason: str,
    task_api_active: str,
    task_api_health_exit: int,
    bridge_active: str,
    bridge_health_exit: int,
    gateway_context: str,
    gateway_last_signal: str,
) -> str:
    reason = trigger_reason.lower()
    gateway_ok = "rpc ok" in gateway_context.lower() and "RPC probe: ok" in gateway_last_signal
    task_api_reason_state = reason_field(reason, "task_api")
    bridge_reason_state = reason_field(reason, "whatsapp_bridge_service")
    gateway_reason_state = reason_field(reason, "gateway")
    task_api_issue = reason_mentions_task_api(reason, task_api_reason_state) or task_api_active != "active" or task_api_health_exit != 0
    bridge_issue = reason_mentions_bridge(reason, bridge_reason_state) or bridge_active != "active" or bridge_health_exit != 0
    bridge_service_issue = reason_mentions_bridge(reason, bridge_reason_state) or bridge_active != "active"
    explicit_gateway_fail = gateway_reason_state == "fail"

    if "stack_startup_timeout" in reason:
        return "confirmar task_api y whatsapp_bridge antes de reintentar start"
    if task_api_issue:
        return "mirar journal de task_api"
    if explicit_gateway_fail and bridge_service_issue:
        return "confirmar gateway RPC antes de reiniciar stack"
    if bridge_issue:
        return "revisar healthcheck de whatsapp_bridge"
    if "self_check_status=" in reason and not gateway_ok:
        return "confirmar gateway RPC antes de reiniciar stack"
    if not gateway_ok:
        return "confirmar gateway RPC antes de reiniciar stack"
    return "mirar summary.txt del ultimo snapshot"


def suggest_second_action(
    trigger_reason: str,
    task_api_active: str,
    task_api_health_exit: int,
    bridge_active: str,
    bridge_health_exit: int,
    gateway_context: str,
    gateway_last_signal: str,
) -> str:
    reason = trigger_reason.lower()
    gateway_ok = "rpc ok" in gateway_context.lower() and "RPC probe: ok" in gateway_last_signal
    task_api_reason_state = reason_field(reason, "task_api")
    bridge_reason_state = reason_field(reason, "whatsapp_bridge_service")
    gateway_reason_state = reason_field(reason, "gateway")
    task_api_issue = reason_mentions_task_api(reason, task_api_reason_state) or task_api_active != "active" or task_api_health_exit != 0
    bridge_issue = reason_mentions_bridge(reason, bridge_reason_state) or bridge_active != "active" or bridge_health_exit != 0
    bridge_service_issue = reason_mentions_bridge(reason, bridge_reason_state) or bridge_active != "active"
    explicit_gateway_fail = gateway_reason_state == "fail"

    if "stack_startup_timeout" in reason and explicit_gateway_fail:
        return "mirar estado del gateway en manifest.json"
    if "stack_startup_timeout" in reason:
        return "mirar pids y puertos relevantes en summary.txt"
    if task_api_issue and explicit_gateway_fail:
        return "mirar estado del gateway en manifest.json"
    if task_api_issue and bridge_service_issue:
        return "mirar journal del servicio whatsapp_bridge"
    if task_api_issue:
        return "confirmar puerto y pid de task_api en summary.txt"
    if explicit_gateway_fail and bridge_service_issue:
        return "mirar journal del servicio whatsapp_bridge"
    if bridge_issue:
        return "mirar journal del servicio whatsapp_bridge"
    if "self_check_status=" in reason and not gateway_ok:
        return "mirar estado del gateway en manifest.json"
    if not gateway_ok:
        return "mirar estado del gateway en manifest.json"
    return "abrir manifest.json si summary.txt no alcanza"


def reason_field(reason: str, key: str) -> str | None:
    for segment in reason.split(";"):
        if "=" not in segment:
            continue
        name, value = segment.split("=", 1)
        if name.strip() == key:
            return value.strip()
    return None


def reason_mentions_task_api(reason: str, reason_state: str | None) -> bool:
    if reason_state is not None:
        return reason_state != "ok"
    return "task_api" in reason


def reason_mentions_bridge(reason: str, reason_state: str | None) -> bool:
    if reason_state is not None:
        return reason_state != "ok"
    return "whatsapp_bridge" in reason


task_api_status = read_json("task_api_status.json")
task_api_health = read_json("task_api_healthcheck.json")
bridge_status = read_json("whatsapp_bridge_status.json")
bridge_health = read_json("whatsapp_bridge_healthcheck.json")

task_api_props = read_props("systemctl_task_api_show.txt")
bridge_props = read_props("systemctl_bridge_show.txt")

task_api_journal = read_text("journal_task_api_tail.txt")
bridge_journal = read_text("journal_bridge_tail.txt")
gateway_status_text = read_text("gateway_status.txt")
gateway_systemd_state = read_text("gateway_systemd_state.txt").strip() or "unknown"
process_table = read_text("process_table.txt")
ports_text = read_text("ports_listening.txt")

task_api_pid = int(task_api_status.get("pid") or 0)
bridge_pid = int(bridge_status.get("pid") or 0)
bridge_runtime = bridge_status.get("runtime")
if not isinstance(bridge_runtime, dict):
    bridge_runtime = {}

process_lines: list[str] = []
for line in process_table.splitlines():
    if not line.strip():
        continue
    if task_api_pid > 0 and str(task_api_pid) in line:
        process_lines.append(line)
        continue
    if bridge_pid > 0 and str(bridge_pid) in line:
        process_lines.append(line)
        continue
    lowered = line.lower()
    if "task_panel_http_server.py" in lowered or "task_whatsapp_bridge_runtime.py" in lowered:
        process_lines.append(line)

port_lines: list[str] = []
port_pattern = f":{task_api_port}"
for line in ports_text.splitlines():
    if not line.strip():
        continue
    if port_pattern in line:
        port_lines.append(line)
        continue
    if task_api_pid > 0 and f"pid={task_api_pid}," in line:
        port_lines.append(line)
        continue
    if bridge_pid > 0 and f"pid={bridge_pid}," in line:
        port_lines.append(line)

(snapshot_dir / "processes_relevant.txt").write_text(
    "\n".join(process_lines) + ("\n" if process_lines else ""),
    encoding="utf-8",
)
(snapshot_dir / "ports_relevant.txt").write_text(
    "\n".join(port_lines) + ("\n" if port_lines else ""),
    encoding="utf-8",
)

task_api_health_exit = read_exit("task_api_healthcheck.exit_code")
bridge_health_exit = read_exit("whatsapp_bridge_healthcheck.exit_code")
stack_health_exit = read_exit("stack_healthcheck.exit_code")

task_api_failure = extract_failure(task_api_status, task_api_health, task_api_props, task_api_journal)
bridge_failure = extract_failure(bridge_status, bridge_health, bridge_props, bridge_journal)

gateway_context = "unavailable"
gateway_last_signal = "(none)"
for line in gateway_status_text.splitlines():
    line = line.strip()
    if not line:
        continue
    if line.startswith("RPC probe:"):
        gateway_last_signal = line
        break
    if line.startswith("Runtime:"):
        gateway_last_signal = line

if gateway_systemd_state == "active":
    if "Runtime: running" in gateway_status_text and "RPC probe: ok" in gateway_status_text:
        gateway_context = "active, runtime running, rpc ok"
    else:
        gateway_context = "active, runtime not fully confirmed"
elif gateway_systemd_state in {"inactive", "failed", "activating", "deactivating"}:
    gateway_context = f"systemd {gateway_systemd_state}"
elif "openclaw command not available" in gateway_status_text:
    gateway_context = "openclaw status unavailable"

task_api_active = task_api_status.get("service_active_state", task_api_props.get("ActiveState", "unknown"))
bridge_active = bridge_status.get("service_active_state", bridge_props.get("ActiveState", "unknown"))
suggested_first_action = suggest_first_action(
    trigger_reason,
    str(task_api_active),
    task_api_health_exit,
    str(bridge_active),
    bridge_health_exit,
    gateway_context,
    gateway_last_signal,
)
second_action = suggest_second_action(
    trigger_reason,
    str(task_api_active),
    task_api_health_exit,
    str(bridge_active),
    bridge_health_exit,
    gateway_context,
    gateway_last_signal,
)

overall = "OK"
if task_api_health_exit != 0 or bridge_health_exit != 0 or stack_health_exit != 0:
    overall = "WARN"
if task_api_active != "active" or bridge_active != "active":
    overall = "FAIL"

summary_lines = [
    "GOLEM HOST DIAGNOSIS",
    "",
    "SNAPSHOT:",
    f"snapshot_dir: {snapshot_dir}",
    f"trigger_mode: {trigger_mode}",
    f"trigger_source: {trigger_source}",
    f"trigger_reason: {trigger_reason}",
    f"trigger_requested_at_utc: {trigger_requested_at}",
    f"auto_cooldown_seconds: {auto_cooldown_seconds}",
    f"overall: {overall}",
    "",
    "CURRENT CONTEXT:",
    f"gateway_context: {gateway_context} | gateway_last_signal: {gateway_last_signal}",
    f"task_api_active: {task_api_active} | whatsapp_bridge_active: {bridge_active}",
    "",
    "DO FIRST:",
    f"suggested_first_action: {suggested_first_action}",
    "",
    "DO NEXT:",
    f"second_action: {second_action}",
    "",
    "READ FIRST:",
    f"look_first: {snapshot_dir / 'summary.txt'}",
    "",
    "READ NEXT:",
    f"look_next: {snapshot_dir / 'manifest.json'}",
    "",
    "DETAILS:",
    f"task_api_service: {task_api_status.get('service_name', '(unknown)')}",
    f"task_api_enabled: {task_api_status.get('service_enabled', task_api_props.get('UnitFileState', 'unknown'))}",
    f"task_api_health: {'OK' if task_api_health_exit == 0 else 'FAIL'}",
    f"task_api_pid: {task_api_pid or '(none)'}",
    f"task_api_base_url: {task_api_status.get('base_url', '(unknown)')}",
    f"task_api_last_failure: {task_api_failure}",
    f"whatsapp_bridge_service: {bridge_status.get('service_name', '(unknown)')}",
    f"whatsapp_bridge_enabled: {bridge_status.get('service_enabled', bridge_props.get('UnitFileState', 'unknown'))}",
    f"whatsapp_bridge_health: {'OK' if bridge_health_exit == 0 else 'FAIL'}",
    f"whatsapp_bridge_pid: {bridge_pid or '(none)'}",
    f"whatsapp_bridge_runtime_status: {bridge_runtime.get('status', '(unknown)')}",
    f"whatsapp_bridge_last_operation: {bridge_runtime.get('last_operation', '(none)')}",
    f"whatsapp_bridge_last_failure: {bridge_failure}",
    f"stack_healthcheck: {'OK' if stack_health_exit == 0 else 'FAIL'}",
    f"ports_relevant_count: {len(port_lines)}",
    f"processes_relevant_count: {len(process_lines)}",
]
(snapshot_dir / "summary.txt").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

manifest = {
    "snapshot_dir": str(snapshot_dir),
    "trigger": {
        "mode": trigger_mode,
        "source": trigger_source,
        "reason": trigger_reason,
        "requested_at_utc": trigger_requested_at,
        "auto_cooldown_seconds": int(float(auto_cooldown_seconds)),
    },
    "overall": overall,
    "gateway": {
        "systemd_state": gateway_systemd_state,
        "context": gateway_context,
        "last_signal": gateway_last_signal,
    },
    "quick_triage": {
        "suggested_first_action": suggested_first_action,
        "second_action": second_action,
    },
    "task_api": {
        "service_name": task_api_status.get("service_name"),
        "active_state": task_api_active,
        "enabled_state": task_api_status.get("service_enabled", task_api_props.get("UnitFileState", "unknown")),
        "health_exit_code": task_api_health_exit,
        "pid": task_api_pid,
        "base_url": task_api_status.get("base_url"),
        "last_failure": task_api_failure,
    },
    "whatsapp_bridge": {
        "service_name": bridge_status.get("service_name"),
        "active_state": bridge_active,
        "enabled_state": bridge_status.get("service_enabled", bridge_props.get("UnitFileState", "unknown")),
        "health_exit_code": bridge_health_exit,
        "pid": bridge_pid,
        "runtime_status": bridge_runtime.get("status"),
        "last_operation": bridge_runtime.get("last_operation"),
        "last_failure": bridge_failure,
    },
    "stack_healthcheck_exit_code": stack_health_exit,
    "relevant_ports": port_lines,
    "relevant_processes": process_lines,
    "files": sorted(path.name for path in snapshot_dir.iterdir()),
}
(snapshot_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY

  LAST_SNAPSHOT_DIR="$snapshot_dir"
  cat "${snapshot_dir}/summary.txt"
  printf 'GOLEM_HOST_DIAGNOSE_SNAPSHOT %s\n' "$snapshot_dir"
}

command_snapshot() {
  local trigger_source="$1"
  local trigger_reason="$2"
  perform_snapshot "manual" "$trigger_source" "$trigger_reason"
}

command_auto() {
  local trigger_source="$1"
  local trigger_reason="$2"
  local now_epoch state_line last_epoch last_source last_reason last_snapshot remaining

  if env_true "${GOLEM_HOST_DIAG_DISABLE_AUTO:-0}"; then
    printf 'GOLEM_HOST_DIAGNOSE_AUTO_SKIPPED disabled source=%s reason=%s\n' "$trigger_source" "$trigger_reason"
    return 0
  fi

  if ! env_true "${GOLEM_HOST_AUTO_DIAGNOSE:-1}"; then
    printf 'GOLEM_HOST_DIAGNOSE_AUTO_SKIPPED disabled source=%s reason=%s\n' "$trigger_source" "$trigger_reason"
    return 0
  fi

  now_epoch="$(date +%s)"
  state_line="$(read_auto_state)"
  last_epoch="$(printf '%s' "$state_line" | cut -f1)"
  last_source="$(printf '%s' "$state_line" | cut -f2)"
  last_reason="$(printf '%s' "$state_line" | cut -f3)"
  last_snapshot="$(printf '%s' "$state_line" | cut -f4)"

  if [ -n "$last_epoch" ] && [ "$last_source" = "$trigger_source" ] && [ "$last_reason" = "$trigger_reason" ]; then
    if [ $((now_epoch - last_epoch)) -lt "${AUTO_DIAG_COOLDOWN_SECONDS%.*}" ]; then
      remaining=$(( ${AUTO_DIAG_COOLDOWN_SECONDS%.*} - (now_epoch - last_epoch) ))
      printf 'GOLEM_HOST_DIAGNOSE_AUTO_SKIPPED cooldown_seconds_remaining=%s source=%s reason=%s last_snapshot=%s\n' \
        "$remaining" "$trigger_source" "$trigger_reason" "${last_snapshot:-"(none)"}"
      return 0
    fi
  fi

  perform_snapshot "auto" "$trigger_source" "$trigger_reason"
  write_auto_state "$trigger_source" "$trigger_reason" "$LAST_SNAPSHOT_DIR" "$now_epoch"
  printf 'GOLEM_HOST_DIAGNOSE_AUTO_TRIGGERED snapshot=%s source=%s reason=%s\n' \
    "$LAST_SNAPSHOT_DIR" "$trigger_source" "$trigger_reason"
}

main() {
  local command="snapshot"
  local trigger_source="${GOLEM_HOST_DIAG_TRIGGER_SOURCE:-manual}"
  local trigger_reason="${GOLEM_HOST_DIAG_TRIGGER_REASON:-manual_request}"

  if [ "$#" -gt 0 ]; then
    case "$1" in
      snapshot)
        command="snapshot"
        shift
        ;;
      auto)
        command="auto"
        shift
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        trigger_source="$2"
        shift 2
        ;;
      --reason)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        trigger_reason="$2"
        shift 2
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  done

  case "$command" in
    snapshot)
      command_snapshot "$trigger_source" "$trigger_reason"
      ;;
    auto)
      command_auto "$trigger_source" "$trigger_reason"
      ;;
  esac
}

main "$@"
