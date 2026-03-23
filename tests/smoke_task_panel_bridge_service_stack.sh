#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
log_feed="$tmpdir/openclaw-follow.jsonl"
bridge_audit="$tmpdir/bridge-audit.jsonl"
bridge_state="$tmpdir/bridge-state.json"
bridge_runtime="$tmpdir/bridge-runtime.json"
api_status_json="$tmpdir/api-status.json"
bridge_status_json="$tmpdir/bridge-status.json"
api_service_name="golem-task-panel-http-stack-smoke-$$.service"
api_service_unit_path="$HOME/.config/systemd/user/$api_service_name"
bridge_service_name="golem-whatsapp-bridge-stack-smoke-$$.service"
bridge_service_unit_path="$HOME/.config/systemd/user/$bridge_service_name"
task_id=""
api_pid=""
bridge_pid=""

cleanup() {
  python3 ./scripts/task_whatsapp_bridge_ctl.py service-uninstall \
    --service-name "$bridge_service_name" \
    --service-unit-path "$bridge_service_unit_path" \
    --state-file "$bridge_state" \
    --runtime-status-file "$bridge_runtime" \
    --audit-file "$bridge_audit" >/dev/null 2>&1 || true
  python3 ./scripts/task_panel_http_ctl.py service-uninstall \
    --service-name "$api_service_name" \
    --service-unit-path "$api_service_unit_path" >/dev/null 2>&1 || true
  if [[ -n "$task_id" && -f "$TASKS_DIR/$task_id.json" ]]; then
    rm -f "$TASKS_DIR/$task_id.json"
  fi
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

python3 ./scripts/task_panel_http_ctl.py start \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_panel_http_ctl.py status \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --json >"$api_status_json"

python3 ./scripts/task_panel_http_ctl.py healthcheck \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

api_pid="$(python3 - "$api_status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_active_state"] == "active", payload
assert payload["api_ready"] is True, payload
print(payload["pid"])
PY
)"

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

python3 ./scripts/task_whatsapp_bridge_ctl.py start \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py status \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --json >"$bridge_status_json"

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

bridge_pid="$(python3 - "$bridge_status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_active_state"] == "active", payload
assert payload["runtime"]["status"] == "running", payload
assert payload["api_ready"] is True, payload
print(payload["pid"])
PY
)"

append_event() {
  local body="$1"
  python3 - "$log_feed" "$body" <<'PY'
import json
import pathlib
import sys
import time

target = pathlib.Path(sys.argv[1])
body = sys.argv[2]
timestamp_ms = int(time.time() * 1000)
payload = {
    "type": "log",
    "time": "2026-03-23T09:10:00.000Z",
    "level": "info",
    "module": "web-inbound",
    "message": (
        '{"module":"web-inbound"} '
        + json.dumps(
            {
                "from": "+156348867",
                "to": "+5491156348667",
                "body": body,
                "mediaPath": None,
                "mediaType": None,
                "timestamp": timestamp_ms,
            },
            ensure_ascii=True,
        )
        + " inbound message"
    ),
    "raw": json.dumps(
        {
            "0": '{"module":"web-inbound"}',
            "1": {
                "from": "+156348867",
                "to": "+5491156348667",
                "body": body,
                "mediaPath": None,
                "mediaType": None,
                "timestamp": timestamp_ms,
            },
            "2": "inbound message",
        },
        ensure_ascii=True,
    ),
}
with target.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, ensure_ascii=True) + "\n")
PY
}

wait_handled_count() {
  local expected="$1"
  python3 - "$bridge_audit" "$expected" <<'PY'
import json
import pathlib
import sys
import time

audit = pathlib.Path(sys.argv[1])
expected = int(sys.argv[2])
deadline = time.time() + 10
while time.time() < deadline:
    if audit.exists():
        entries = [
            json.loads(line)
            for line in audit.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        handled = [entry for entry in entries if entry.get("type") == "handled"]
        if len(handled) >= expected:
            raise SystemExit(0)
    time.sleep(0.2)
raise SystemExit(f"timed out waiting for handled_count={expected}")
PY
}

append_event "tasks summary"
wait_handled_count 1
append_event "task create title=Smoke bridge api service stack ; objective=Validate bridge with serviceified task api ; type=smoke-bridge-api-service-stack ; owner=bridge-stack ; accept=service stack create"
wait_handled_count 2

task_id="$(python3 - "$bridge_audit" <<'PY'
import json
import pathlib
import sys

entries = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
for entry in reversed(entries):
    if entry.get("type") == "handled" and entry.get("operation") == "create":
        print(entry.get("response_details", {}).get("task_id", ""))
        break
PY
)"

[[ -n "$task_id" ]] || {
  echo "FAIL: bridge/api stack smoke did not create a task" >&2
  exit 1
}

append_event "task close ${task_id} status=done ; note=service stack close ; owner=bridge-stack"
wait_handled_count 3

python3 ./scripts/task_panel_http_ctl.py restart \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_panel_http_ctl.py healthcheck \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

append_event "tasks summary"
wait_handled_count 4

python3 ./scripts/task_whatsapp_bridge_ctl.py stop \
  --service \
  --service-name "$bridge_service_name" \
  --service-unit-path "$bridge_service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_panel_http_ctl.py stop \
  --service \
  --service-name "$api_service_name" \
  --service-unit-path "$api_service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 - "$TASKS_DIR/$task_id.json" "$bridge_audit" "$bridge_runtime" "$api_service_name" "$bridge_service_name" "$api_pid" "$bridge_pid" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

task_path = pathlib.Path(sys.argv[1])
audit_path = pathlib.Path(sys.argv[2])
runtime_path = pathlib.Path(sys.argv[3])
api_service_name = sys.argv[4]
bridge_service_name = sys.argv[5]
api_pid = int(sys.argv[6])
bridge_pid = int(sys.argv[7])

task = json.loads(task_path.read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert task["source_channel"] == "whatsapp", task["source_channel"]
assert task["owner"] == "bridge-stack", task["owner"]
assert task["closure_note"] == "service stack close", task["closure_note"]

entries = [json.loads(line) for line in audit_path.read_text(encoding="utf-8").splitlines() if line.strip()]
handled = [entry for entry in entries if entry.get("type") == "handled"]
ops = [entry.get("operation") for entry in handled]
assert ops == ["summary", "create", "close", "summary"], ops

runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
assert runtime["status"] == "stopped", runtime
assert runtime["stop_reason"] == "signal", runtime
assert runtime["child_pid"] == 0, runtime

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

print("SMOKE_TASK_PANEL_BRIDGE_SERVICE_STACK_OK")
print(f"TASK_PANEL_BRIDGE_STACK_API_PID {api_pid}")
print(f"TASK_PANEL_BRIDGE_STACK_BRIDGE_PID {bridge_pid}")
print(f"TASK_PANEL_BRIDGE_STACK_HANDLED {len(handled)}")
PY
