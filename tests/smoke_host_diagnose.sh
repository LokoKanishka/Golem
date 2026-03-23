#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
log_feed="$tmpdir/openclaw-follow.jsonl"
bridge_audit="$tmpdir/bridge-audit.jsonl"
bridge_state="$tmpdir/bridge-state.json"
bridge_runtime="$tmpdir/bridge-runtime.json"
diagnostics_root="$tmpdir/diagnostics-host"
diagnose_stdout="$tmpdir/diagnose.txt"
api_service_name="golem-task-panel-http-diagnose-smoke-$$.service"
api_service_unit_path="$HOME/.config/systemd/user/$api_service_name"
bridge_service_name="golem-whatsapp-bridge-diagnose-smoke-$$.service"
bridge_service_unit_path="$HOME/.config/systemd/user/$bridge_service_name"

cleanup() {
  GOLEM_TASK_API_SERVICE_NAME="$api_service_name" \
  GOLEM_TASK_API_SERVICE_UNIT_PATH="$api_service_unit_path" \
  GOLEM_TASK_API_HOST="127.0.0.1" \
  GOLEM_TASK_API_PORT="${port:-8765}" \
  GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME="$bridge_service_name" \
  GOLEM_WHATSAPP_BRIDGE_SERVICE_UNIT_PATH="$bridge_service_unit_path" \
  GOLEM_WHATSAPP_BRIDGE_BASE_URL="${base_url:-http://127.0.0.1:8765}" \
  GOLEM_WHATSAPP_BRIDGE_STATE_FILE="$bridge_state" \
  GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE="$bridge_runtime" \
  GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE="$bridge_audit" \
  ./scripts/golem_host_stack_ctl.sh stop >/dev/null 2>&1 || true
  python3 ./scripts/task_whatsapp_bridge_ctl.py service-uninstall \
    --service-name "$bridge_service_name" \
    --service-unit-path "$bridge_service_unit_path" \
    --state-file "$bridge_state" \
    --runtime-status-file "$bridge_runtime" \
    --audit-file "$bridge_audit" >/dev/null 2>&1 || true
  python3 ./scripts/task_panel_http_ctl.py service-uninstall \
    --service-name "$api_service_name" \
    --service-unit-path "$api_service_unit_path" >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

touch "$log_feed"
base_url="http://127.0.0.1:${port}"

python3 ./scripts/task_panel_http_ctl.py service-install \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --enable >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py service-install \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --log-command "tail -n +1 -f $log_feed" \
  --send-dry-run \
  --enable >/dev/null

GOLEM_TASK_API_SERVICE_NAME="$api_service_name" \
GOLEM_TASK_API_SERVICE_UNIT_PATH="$api_service_unit_path" \
GOLEM_TASK_API_HOST="127.0.0.1" \
GOLEM_TASK_API_PORT="$port" \
GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME="$bridge_service_name" \
GOLEM_WHATSAPP_BRIDGE_SERVICE_UNIT_PATH="$bridge_service_unit_path" \
GOLEM_WHATSAPP_BRIDGE_BASE_URL="$base_url" \
GOLEM_WHATSAPP_BRIDGE_STATE_FILE="$bridge_state" \
GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE="$bridge_runtime" \
GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE="$bridge_audit" \
./scripts/golem_host_stack_ctl.sh start >/dev/null

GOLEM_TASK_API_SERVICE_NAME="$api_service_name" \
GOLEM_TASK_API_SERVICE_UNIT_PATH="$api_service_unit_path" \
GOLEM_TASK_API_HOST="127.0.0.1" \
GOLEM_TASK_API_PORT="$port" \
GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME="$bridge_service_name" \
GOLEM_WHATSAPP_BRIDGE_SERVICE_UNIT_PATH="$bridge_service_unit_path" \
GOLEM_WHATSAPP_BRIDGE_BASE_URL="$base_url" \
GOLEM_WHATSAPP_BRIDGE_STATE_FILE="$bridge_state" \
GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE="$bridge_runtime" \
GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE="$bridge_audit" \
GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
./scripts/golem_host_stack_ctl.sh diagnose >"$diagnose_stdout"

python3 - "$diagnose_stdout" "$diagnostics_root" "$api_service_name" "$bridge_service_name" "$port" <<'PY'
import json
import pathlib
import sys

diagnose_stdout = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[2])
api_service_name = sys.argv[3]
bridge_service_name = sys.argv[4]
port = sys.argv[5]

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]

required = [
    "summary.txt",
    "manifest.json",
    "meta.env",
    "stack_status.txt",
    "stack_healthcheck.txt",
    "task_api_status.json",
    "task_api_healthcheck.json",
    "whatsapp_bridge_status.json",
    "whatsapp_bridge_healthcheck.json",
    "systemctl_task_api_status.txt",
    "systemctl_bridge_status.txt",
    "journal_task_api_tail.txt",
    "journal_bridge_tail.txt",
    "processes_relevant.txt",
    "ports_relevant.txt",
]
for name in required:
    assert (snapshot_dir / name).exists(), name

summary = (snapshot_dir / "summary.txt").read_text(encoding="utf-8")
assert "GOLEM HOST DIAGNOSIS" in summary, summary
assert "trigger_mode: manual" in summary, summary
assert "trigger_source: golem_host_stack_ctl" in summary, summary
assert "trigger_reason: manual_stack_diagnose" in summary, summary
assert "overall: OK" in summary, summary
assert f"task_api_service: {api_service_name}" in summary, summary
assert f"whatsapp_bridge_service: {bridge_service_name}" in summary, summary
assert "task_api_health: OK" in summary, summary
assert "whatsapp_bridge_health: OK" in summary, summary

manifest = json.loads((snapshot_dir / "manifest.json").read_text(encoding="utf-8"))
assert manifest["overall"] == "OK", manifest
assert manifest["trigger"]["mode"] == "manual", manifest
assert manifest["trigger"]["source"] == "golem_host_stack_ctl", manifest
assert manifest["trigger"]["reason"] == "manual_stack_diagnose", manifest
assert manifest["task_api"]["service_name"] == api_service_name, manifest
assert manifest["task_api"]["health_exit_code"] == 0, manifest
assert manifest["whatsapp_bridge"]["service_name"] == bridge_service_name, manifest
assert manifest["whatsapp_bridge"]["health_exit_code"] == 0, manifest
assert any(f":{port}" in line for line in manifest["relevant_ports"]), manifest["relevant_ports"]

task_api_status = json.loads((snapshot_dir / "task_api_status.json").read_text(encoding="utf-8"))
assert task_api_status["service_active_state"] == "active", task_api_status
assert task_api_status["api_ready"] is True, task_api_status

bridge_status = json.loads((snapshot_dir / "whatsapp_bridge_status.json").read_text(encoding="utf-8"))
assert bridge_status["service_active_state"] == "active", bridge_status
assert bridge_status["runtime"]["status"] == "running", bridge_status

ports = (snapshot_dir / "ports_relevant.txt").read_text(encoding="utf-8")
assert f":{port}" in ports, ports

processes = (snapshot_dir / "processes_relevant.txt").read_text(encoding="utf-8")
assert "task_panel_http_server.py" in processes, processes
assert "task_whatsapp_bridge_runtime.py" in processes, processes

assert "GOLEM_HOST_DIAGNOSE_SNAPSHOT" in diagnose_stdout, diagnose_stdout
assert str(snapshot_dir) in diagnose_stdout, diagnose_stdout

print("SMOKE_HOST_DIAGNOSE_OK")
print(f"HOST_DIAGNOSE_SNAPSHOT {snapshot_dir}")
print(f"HOST_DIAGNOSE_API_SERVICE {api_service_name}")
print(f"HOST_DIAGNOSE_BRIDGE_SERVICE {bridge_service_name}")
PY
