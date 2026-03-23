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
first_healthcheck_txt="$tmpdir/first-healthcheck.txt"
second_healthcheck_txt="$tmpdir/second-healthcheck.txt"
api_status_json="$tmpdir/api-status.json"
bridge_status_json="$tmpdir/bridge-status.json"
api_service_name="golem-task-panel-http-auto-diag-smoke-$$.service"
api_service_unit_path="$HOME/.config/systemd/user/$api_service_name"
bridge_service_name="golem-whatsapp-bridge-auto-diag-smoke-$$.service"
bridge_service_unit_path="$HOME/.config/systemd/user/$bridge_service_name"
api_pid=""
bridge_pid=""

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

python3 ./scripts/task_panel_http_ctl.py status \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --json >"$api_status_json"

python3 ./scripts/task_whatsapp_bridge_ctl.py status \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --json >"$bridge_status_json"

api_pid="$(python3 - "$api_status_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["pid"])
PY
)"

bridge_pid="$(python3 - "$bridge_status_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["pid"])
PY
)"

python3 ./scripts/task_whatsapp_bridge_ctl.py stop \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

set +e
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
GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS=300 \
./scripts/golem_host_stack_ctl.sh healthcheck >"$first_healthcheck_txt" 2>&1
first_exit=$?
set -e
[ "$first_exit" -ne 0 ] || {
  echo "FAIL: first healthcheck should fail" >&2
  exit 1
}

set +e
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
GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS=300 \
./scripts/golem_host_stack_ctl.sh healthcheck >"$second_healthcheck_txt" 2>&1
second_exit=$?
set -e
[ "$second_exit" -ne 0 ] || {
  echo "FAIL: second healthcheck should fail" >&2
  exit 1
}

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
./scripts/golem_host_stack_ctl.sh stop >/dev/null

python3 - "$diagnostics_root" "$first_healthcheck_txt" "$second_healthcheck_txt" "$api_service_name" "$bridge_service_name" "$api_pid" "$bridge_pid" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

diagnostics_root = pathlib.Path(sys.argv[1])
first_output = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
second_output = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
api_service_name = sys.argv[4]
bridge_service_name = sys.argv[5]
api_pid = int(sys.argv[6])
bridge_pid = int(sys.argv[7])

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]

summary = (snapshot_dir / "summary.txt").read_text(encoding="utf-8")
assert "trigger_mode: auto" in summary, summary
assert "trigger_source: golem_host_stack_ctl" in summary, summary
assert "trigger_reason: stack_healthcheck_failed" in summary, summary
assert "overall: FAIL" in summary or "overall: WARN" in summary, summary

manifest = json.loads((snapshot_dir / "manifest.json").read_text(encoding="utf-8"))
assert manifest["trigger"]["mode"] == "auto", manifest
assert manifest["trigger"]["source"] == "golem_host_stack_ctl", manifest
assert manifest["trigger"]["reason"] == "stack_healthcheck_failed", manifest
assert manifest["task_api"]["service_name"] == api_service_name, manifest
assert manifest["whatsapp_bridge"]["service_name"] == bridge_service_name, manifest
assert manifest["whatsapp_bridge"]["health_exit_code"] != 0, manifest

assert "GOLEM_HOST_DIAGNOSE_AUTO_TRIGGERED" in first_output, first_output
assert str(snapshot_dir) in first_output, first_output
assert "GOLEM_HOST_DIAGNOSE_AUTO_SKIPPED" in second_output, second_output
assert str(snapshot_dir) in second_output, second_output

for service_name in (api_service_name, bridge_service_name):
    show = subprocess.run(
        ["systemctl", "--user", "show", service_name, "--property", "ActiveState,SubState,MainPID", "--no-page"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert show.returncode == 0, show.stderr
    payload = {}
    for line in show.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            payload[key] = value
    assert payload["ActiveState"] == "inactive", payload
    assert payload["SubState"] == "dead", payload
    assert payload["MainPID"] in {"0", ""}, payload

for pid in (api_pid, bridge_pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pass
    else:
        raise AssertionError(f"service pid still alive: {pid}")

print("SMOKE_HOST_AUTO_DIAGNOSE_FAILURE_OK")
print(f"HOST_AUTO_DIAGNOSE_SNAPSHOT {snapshot_dir}")
print(f"HOST_AUTO_DIAGNOSE_API_PID {api_pid}")
print(f"HOST_AUTO_DIAGNOSE_BRIDGE_PID {bridge_pid}")
PY
