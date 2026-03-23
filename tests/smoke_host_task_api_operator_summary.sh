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
api_service_name="golem-task-panel-http-task-api-smoke-$$.service"
api_service_unit_path="$HOME/.config/systemd/user/$api_service_name"
bridge_service_name="golem-whatsapp-bridge-task-api-smoke-$$.service"
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

python3 ./scripts/task_panel_http_ctl.py stop \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

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
  echo "FAIL: healthcheck should fail for task_api smoke" >&2
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
import json
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
summary = summary_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "GOLEM HOST FAILURE SUMMARY" in healthcheck, healthcheck
assert "reason: stack_healthcheck_failed" in healthcheck, healthcheck
assert f"services: task_api={api_service_name} whatsapp_bridge={bridge_service_name}" in healthcheck, healthcheck
assert "gateway_context:" in healthcheck, healthcheck
assert "gateway_last_signal:" in healthcheck, healthcheck
assert "suggested_first_action: mirar journal de task_api" in healthcheck, healthcheck
assert "second_action:" not in healthcheck, healthcheck
assert f"snapshot: {snapshot_dir}" in healthcheck, healthcheck
assert f"look_first: {summary_path}" in healthcheck, healthcheck
assert f"look_next: {manifest_path}" in healthcheck, healthcheck
assert "helper: ./scripts/golem_host_last_snapshot.sh" in healthcheck, healthcheck
assert len([line for line in healthcheck.splitlines() if line.strip()]) <= 13, healthcheck

assert "GOLEM HOST LAST SNAPSHOT" in helper, helper
assert "trigger_reason: stack_healthcheck_failed" in helper, helper
assert "gateway_context / gateway_last_signal: active, runtime running, rpc ok | RPC probe: ok" in helper, helper
assert "task_api_active / whatsapp_bridge_active: inactive | active" in helper, helper
assert "suggested_first_action: mirar journal de task_api" in helper, helper
assert "second_action: confirmar puerto y pid de task_api en summary.txt" in helper, helper
assert f"look_first: {summary_path}" in helper, helper
assert f"look_next: {manifest_path}" in helper, helper

assert "suggested_first_action: mirar journal de task_api" in summary, summary
assert "second_action: confirmar puerto y pid de task_api en summary.txt" in summary, summary
assert "gateway_context: active, runtime running, rpc ok | gateway_last_signal: RPC probe: ok" in summary, summary
assert "task_api_active: inactive | whatsapp_bridge_active: active" in summary, summary

assert manifest["quick_triage"]["suggested_first_action"] == "mirar journal de task_api", manifest
assert manifest["quick_triage"]["second_action"] == "confirmar puerto y pid de task_api en summary.txt", manifest
assert manifest["task_api"]["service_name"] == api_service_name, manifest
assert manifest["task_api"]["active_state"] == "inactive", manifest
assert manifest["whatsapp_bridge"]["service_name"] == bridge_service_name, manifest
assert manifest["whatsapp_bridge"]["active_state"] == "active", manifest

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

print("SMOKE_HOST_TASK_API_OPERATOR_SUMMARY_OK")
print(f"HOST_TASK_API_OPERATOR_SNAPSHOT {snapshot_dir}")
print(f"HOST_TASK_API_OPERATOR_LOOK_FIRST {summary_path}")
PY
