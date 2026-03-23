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

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_diagnose.sh
  ./scripts/golem_host_diagnose.sh snapshot

Env overrides:
  GOLEM_HOST_DIAGNOSTICS_ROOT
  GOLEM_HOST_DIAG_JOURNAL_LINES
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

main() {
  if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
  fi
  if [ "$#" -eq 1 ] && [ "$1" != "snapshot" ]; then
    usage >&2
    exit 2
  fi

  cd "$REPO_ROOT"

  local snapshot_ts snapshot_dir
  snapshot_ts="$(date -u +%Y%m%dT%H%M%SZ)"
  snapshot_dir="${DIAGNOSTICS_ROOT}/${snapshot_ts}-golem-host-diagnose"
  mkdir -p "$snapshot_dir"

  write_text "${snapshot_dir}/meta.env" \
    "snapshot_timestamp_utc=${snapshot_ts}" \
    "repo_root=${REPO_ROOT}" \
    "user=$(id -un)" \
    "hostname=$(hostname)" \
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
    ./scripts/golem_host_stack_ctl.sh healthcheck

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

  python3 - "$snapshot_dir" "$TASK_API_PORT" <<'PY'
import json
import pathlib
import sys
from typing import Any

snapshot_dir = pathlib.Path(sys.argv[1])
task_api_port = sys.argv[2]


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


task_api_status = read_json("task_api_status.json")
task_api_health = read_json("task_api_healthcheck.json")
bridge_status = read_json("whatsapp_bridge_status.json")
bridge_health = read_json("whatsapp_bridge_healthcheck.json")

task_api_props = read_props("systemctl_task_api_show.txt")
bridge_props = read_props("systemctl_bridge_show.txt")

task_api_journal = read_text("journal_task_api_tail.txt")
bridge_journal = read_text("journal_bridge_tail.txt")
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

task_api_active = task_api_status.get("service_active_state", task_api_props.get("ActiveState", "unknown"))
bridge_active = bridge_status.get("service_active_state", bridge_props.get("ActiveState", "unknown"))

overall = "OK"
if task_api_health_exit != 0 or bridge_health_exit != 0 or stack_health_exit != 0:
    overall = "WARN"
if task_api_active != "active" or bridge_active != "active":
    overall = "FAIL"

summary_lines = [
    "GOLEM HOST DIAGNOSIS",
    f"snapshot_dir: {snapshot_dir}",
    f"overall: {overall}",
    f"task_api_service: {task_api_status.get('service_name', '(unknown)')}",
    f"task_api_enabled: {task_api_status.get('service_enabled', task_api_props.get('UnitFileState', 'unknown'))}",
    f"task_api_active: {task_api_active}",
    f"task_api_health: {'OK' if task_api_health_exit == 0 else 'FAIL'}",
    f"task_api_pid: {task_api_pid or '(none)'}",
    f"task_api_base_url: {task_api_status.get('base_url', '(unknown)')}",
    f"task_api_last_failure: {task_api_failure}",
    f"whatsapp_bridge_service: {bridge_status.get('service_name', '(unknown)')}",
    f"whatsapp_bridge_enabled: {bridge_status.get('service_enabled', bridge_props.get('UnitFileState', 'unknown'))}",
    f"whatsapp_bridge_active: {bridge_active}",
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
    "overall": overall,
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

  cat "${snapshot_dir}/summary.txt"
  printf 'GOLEM_HOST_DIAGNOSE_SNAPSHOT %s\n' "$snapshot_dir"
}

main "$@"
