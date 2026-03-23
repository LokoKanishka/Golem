#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
bridge_audit="$tmpdir/bridge-audit.jsonl"
bridge_state="$tmpdir/bridge-state.json"
bridge_runtime="$tmpdir/bridge-runtime.json"
log_feed="$tmpdir/openclaw-follow.jsonl"
status_json="$tmpdir/status.json"
logs_txt="$tmpdir/service-logs.txt"
service_name="golem-whatsapp-bridge-smoke-$$.service"
service_unit_path="$HOME/.config/systemd/user/$service_name"
server_pid=""
task_id=""
first_pid=""
second_pid=""

cleanup() {
  python3 ./scripts/task_whatsapp_bridge_ctl.py service-uninstall \
    --service-name "$service_name" \
    --service-unit-path "$service_unit_path" \
    --state-file "$bridge_state" \
    --runtime-status-file "$bridge_runtime" \
    --audit-file "$bridge_audit" >/dev/null 2>&1 || true
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
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

python3 ./scripts/task_panel_http_server.py --host 127.0.0.1 --port "$port" >"$server_log" 2>&1 &
server_pid="$!"

python3 - "$port" <<'PY'
import sys
import time
import urllib.request

port = int(sys.argv[1])
url = f"http://127.0.0.1:{port}/tasks/summary"
deadline = time.time() + 10
while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.2)
raise SystemExit("server did not become ready")
PY

touch "$log_feed"
base_url="http://127.0.0.1:${port}"

python3 ./scripts/task_whatsapp_bridge_ctl.py service-install \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --log-command "tail -n +1 -f $log_feed" \
  --send-dry-run \
  --enable >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py start \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py status \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --json >"$status_json"

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

first_pid="$(python3 - "$status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_mode"] is True, payload
assert payload["service_active_state"] == "active", payload
assert payload["service_enabled"] in {"enabled", "enabled-runtime"}, payload
assert payload["runtime"]["status"] == "running", payload
assert payload["running"] is True, payload
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
    "time": "2026-03-23T08:30:00.000Z",
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
append_event "tasks list limit 2"
wait_handled_count 2
append_event "task show task-20260313T003348Z-06ef71e3"
wait_handled_count 3
append_event "task create title=Smoke WhatsApp bridge service ; objective=Validate systemd user service mode ; type=smoke-whatsapp-bridge-service ; owner=whatsapp-service ; accept=service mode create"
wait_handled_count 4

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
  echo "FAIL: service smoke did not create a task" >&2
  exit 1
}

append_event "task update ${task_id} status=running ; owner=whatsapp-service ; title=Smoke WhatsApp bridge service updated ; objective=Validate systemd user service mode updated ; note=service mode update ; append_accept=service mode update"
wait_handled_count 5
append_event "task close ${task_id} status=done ; note=service mode close ; owner=whatsapp-service"
wait_handled_count 6

python3 ./scripts/task_whatsapp_bridge_ctl.py restart \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py status \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --json >"$status_json"

second_pid="$(python3 - "$status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_active_state"] == "active", payload
assert payload["runtime"]["status"] == "running", payload
print(payload["pid"])
PY
)"

append_event "tasks summary"
wait_handled_count 7

python3 ./scripts/task_whatsapp_bridge_ctl.py logs \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --lines 200 >"$logs_txt"

python3 ./scripts/task_whatsapp_bridge_ctl.py stop \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --base-url "$base_url" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 - "$bridge_audit" "$TASKS_DIR/$task_id.json" "$bridge_runtime" "$first_pid" "$second_pid" "$service_name" "$service_unit_path" "$logs_txt" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

audit_path = pathlib.Path(sys.argv[1])
task_path = pathlib.Path(sys.argv[2])
runtime_path = pathlib.Path(sys.argv[3])
first_pid = int(sys.argv[4])
second_pid = int(sys.argv[5])
service_name = sys.argv[6]
service_unit_path = pathlib.Path(sys.argv[7])
logs_path = pathlib.Path(sys.argv[8])

entries = [json.loads(line) for line in audit_path.read_text(encoding="utf-8").splitlines() if line.strip()]
handled = [entry for entry in entries if entry.get("type") == "handled"]
ops = [entry.get("operation") for entry in handled]
assert ops[:6] == ["summary", "list", "show", "create", "update", "close"], ops
assert ops[-1] == "summary", ops

task = json.loads(task_path.read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert task["source_channel"] == "whatsapp", task["source_channel"]
assert task["owner"] == "whatsapp-service", task["owner"]
assert task["closure_note"] == "service mode close", task["closure_note"]

runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
assert runtime["status"] == "stopped", runtime
assert runtime["stop_reason"] == "signal", runtime
assert len(handled) >= 7, handled
assert runtime["handled_count"] >= 1, runtime
assert runtime["child_pid"] == 0, runtime

assert first_pid > 0, first_pid
assert second_pid > 0, second_pid
assert first_pid != second_pid, (first_pid, second_pid)

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

for pid in (first_pid, second_pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pass
    else:
        raise AssertionError(f"bridge pid still alive: {pid}")

logs_text = logs_path.read_text(encoding="utf-8")
assert "TASK_WHATSAPP_BRIDGE_SERVICE_PREFLIGHT_OK" in logs_text, logs_text
assert '"type": "handled"' in logs_text, logs_text

assert service_unit_path.exists(), service_unit_path

print("SMOKE_WHATSAPP_BRIDGE_SERVICE_OK")
print(f"WHATSAPP_BRIDGE_SERVICE_NAME {service_name}")
print(f"WHATSAPP_BRIDGE_SERVICE_FIRST_PID {first_pid}")
print(f"WHATSAPP_BRIDGE_SERVICE_SECOND_PID {second_pid}")
print(f"WHATSAPP_BRIDGE_SERVICE_HANDLED {len(handled)}")
PY
