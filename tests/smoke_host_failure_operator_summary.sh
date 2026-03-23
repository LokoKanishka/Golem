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
auto_state="$tmpdir/auto-state.json"
healthcheck_txt="$tmpdir/healthcheck.txt"
helper_txt="$tmpdir/helper.txt"
api_service_name="golem-task-panel-http-ux-smoke-$$.service"
api_service_unit_path="$HOME/.config/systemd/user/$api_service_name"
bridge_service_name="golem-whatsapp-bridge-ux-smoke-$$.service"
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

api_pid="$(python3 ./scripts/task_panel_http_ctl.py status \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])')"

bridge_pid="$(python3 ./scripts/task_whatsapp_bridge_ctl.py status \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])')"

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
GOLEM_HOST_AUTO_DIAGNOSE_STATE_FILE="$auto_state" \
GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS=300 \
./scripts/golem_host_stack_ctl.sh healthcheck >"$healthcheck_txt" 2>&1
health_exit=$?
set -e
[ "$health_exit" -ne 0 ] || {
  echo "FAIL: healthcheck should fail for UX smoke" >&2
  exit 1
}

GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
./scripts/golem_host_last_snapshot.sh >"$helper_txt"

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

python3 - "$healthcheck_txt" "$helper_txt" "$diagnostics_root" "$api_service_name" "$bridge_service_name" "$api_pid" "$bridge_pid" <<'PY'
import os
import pathlib
import subprocess
import sys

healthcheck = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
helper = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[3])
api_service_name = sys.argv[4]
bridge_service_name = sys.argv[5]
api_pid = int(sys.argv[6])
bridge_pid = int(sys.argv[7])

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]
summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"

assert "GOLEM HOST FAILURE SUMMARY" in healthcheck, healthcheck
assert "reason: stack_healthcheck_failed" in healthcheck, healthcheck
assert f"services: task_api={api_service_name} whatsapp_bridge={bridge_service_name}" in healthcheck, healthcheck
assert "gateway_context:" in healthcheck, healthcheck
assert "gateway_last_signal:" in healthcheck, healthcheck
assert "suggested_first_action: revisar healthcheck de whatsapp_bridge" in healthcheck, healthcheck
assert "second_action:" not in healthcheck, healthcheck
assert f"snapshot: {snapshot_dir}" in healthcheck, healthcheck
assert f"look_first: {summary_path}" in healthcheck, healthcheck
assert f"look_next: {manifest_path}" in healthcheck, healthcheck
assert "helper: ./scripts/golem_host_last_snapshot.sh" in healthcheck, healthcheck
assert "GOLEM HOST DIAGNOSIS" not in healthcheck, healthcheck
assert len([line for line in healthcheck.splitlines() if line.strip()]) <= 13, healthcheck

assert "GOLEM HOST LAST SNAPSHOT" in helper, helper
assert "SNAPSHOT:" in helper, helper
assert "CURRENT CONTEXT:" in helper, helper
assert "DO FIRST:" in helper, helper
assert "DO NEXT:" in helper, helper
assert "READ FIRST:" in helper, helper
assert "READ NEXT:" in helper, helper
assert f"snapshot_dir: {snapshot_dir}" in helper, helper
assert "trigger_reason: stack_healthcheck_failed" in helper, helper
assert "gateway_context:" in helper, helper
assert "gateway_last_signal:" in helper, helper
assert "suggested_first_action: revisar healthcheck de whatsapp_bridge" in helper, helper
assert "second_action: mirar journal del servicio whatsapp_bridge" in helper, helper
assert f"look_first: {summary_path}" in helper, helper
assert f"look_next: {manifest_path}" in helper, helper
assert helper.index("DO FIRST:") < helper.index("suggested_first_action:"), helper
assert helper.index("DO NEXT:") < helper.index("second_action:"), helper
assert helper.index("READ FIRST:") < helper.index("look_first:"), helper
assert helper.index("READ NEXT:") < helper.index("look_next:"), helper

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

print("SMOKE_HOST_FAILURE_OPERATOR_SUMMARY_OK")
print(f"HOST_FAILURE_OPERATOR_SNAPSHOT {snapshot_dir}")
print(f"HOST_FAILURE_OPERATOR_LOOK_FIRST {summary_path}")
PY
