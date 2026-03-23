#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
bridge_log="$tmpdir/bridge.log"
bridge_audit="$tmpdir/bridge-audit.jsonl"
bridge_state="$tmpdir/bridge-state.json"
bridge_runtime="$tmpdir/bridge-runtime.json"
bridge_pid_file="$tmpdir/bridge.pid"
log_feed="$tmpdir/openclaw-follow.jsonl"
server_pid=""
bridge_pid=""
task_id=""

cleanup() {
  python3 ./scripts/task_whatsapp_bridge_ctl.py stop \
    --pid-file "$bridge_pid_file" \
    --runtime-status-file "$bridge_runtime" \
    --state-file "$bridge_state" \
    --log-file "$bridge_log" \
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

python3 ./scripts/task_whatsapp_bridge_ctl.py start \
  --base-url "$base_url" \
  --pid-file "$bridge_pid_file" \
  --log-file "$bridge_log" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" \
  --log-command "tail -n +1 -f $log_feed" \
  --send-dry-run >/dev/null

bridge_pid="$(cat "$bridge_pid_file")"

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --base-url "$base_url" \
  --pid-file "$bridge_pid_file" \
  --log-file "$bridge_log" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

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
    "time": "2026-03-23T08:10:00.000Z",
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
append_event "task create title=Smoke WhatsApp runtime hardening ; objective=Validate hardened runtime bridge ; type=smoke-whatsapp-runtime-hardening ; owner=whatsapp-hardening ; accept=runtime hardening create"
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
  echo "FAIL: hardening smoke did not create a task" >&2
  exit 1
}

append_event "task update ${task_id} status=running ; owner=whatsapp-hardening ; title=Smoke WhatsApp runtime hardening updated ; objective=Validate hardened runtime bridge updated ; note=runtime hardening update ; append_accept=runtime hardening update"
wait_handled_count 5
append_event "task close ${task_id} status=done ; note=runtime hardening close ; owner=whatsapp-hardening"
wait_handled_count 6

python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck \
  --base-url "$base_url" \
  --pid-file "$bridge_pid_file" \
  --log-file "$bridge_log" \
  --state-file "$bridge_state" \
  --runtime-status-file "$bridge_runtime" \
  --audit-file "$bridge_audit" >/dev/null

python3 ./scripts/task_whatsapp_bridge_ctl.py stop \
  --pid-file "$bridge_pid_file" \
  --runtime-status-file "$bridge_runtime" \
  --state-file "$bridge_state" \
  --log-file "$bridge_log" \
  --audit-file "$bridge_audit" >/dev/null

python3 - "$bridge_audit" "$TASKS_DIR/$task_id.json" "$bridge_runtime" "$bridge_pid" "$bridge_pid_file" <<'PY'
import json
import os
import pathlib
import sys

audit_path = pathlib.Path(sys.argv[1])
task_path = pathlib.Path(sys.argv[2])
runtime_path = pathlib.Path(sys.argv[3])
bridge_pid = int(sys.argv[4])
pid_file = pathlib.Path(sys.argv[5])

entries = [json.loads(line) for line in audit_path.read_text(encoding="utf-8").splitlines() if line.strip()]
handled = [entry for entry in entries if entry.get("type") == "handled"]
ops = [entry.get("operation") for entry in handled]
assert ops == ["summary", "list", "show", "create", "update", "close"], ops

task = json.loads(task_path.read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert task["source_channel"] == "whatsapp", task["source_channel"]
assert task["owner"] == "whatsapp-hardening", task["owner"]
assert task["closure_note"] == "runtime hardening close", task["closure_note"]

runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
assert runtime["status"] == "stopped", runtime
assert runtime["stop_reason"] == "signal", runtime
assert runtime["handled_count"] >= 6, runtime
assert runtime["child_pid"] == 0, runtime
assert runtime["restart_count"] >= 0, runtime

assert not pid_file.exists(), pid_file
try:
    os.kill(bridge_pid, 0)
except OSError:
    pass
else:
    raise AssertionError(f"bridge pid still alive: {bridge_pid}")

print("SMOKE_WHATSAPP_BRIDGE_RUNTIME_HARDENING_OK")
print(f"WHATSAPP_BRIDGE_HARDENING_TASK_ID {task['id']}")
print(f"WHATSAPP_BRIDGE_HARDENING_FINAL_STATUS {task['status']}")
print(f"WHATSAPP_BRIDGE_HARDENING_STOP_REASON {runtime['stop_reason']}")
print(f"WHATSAPP_BRIDGE_HARDENING_HANDLED {runtime['handled_count']}")
PY
