#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
status_json="$tmpdir/status.json"
logs_txt="$tmpdir/service-logs.txt"
service_name="golem-task-panel-http-smoke-$$.service"
service_unit_path="$HOME/.config/systemd/user/$service_name"
task_id=""
first_pid=""
second_pid=""

cleanup() {
  python3 ./scripts/task_panel_http_ctl.py service-uninstall \
    --service-name "$service_name" \
    --service-unit-path "$service_unit_path" >/dev/null 2>&1 || true
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

python3 ./scripts/task_panel_http_ctl.py service-install \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --enable >/dev/null

python3 ./scripts/task_panel_http_ctl.py start \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_panel_http_ctl.py status \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --json >"$status_json"

python3 ./scripts/task_panel_http_ctl.py healthcheck \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

first_pid="$(python3 - "$status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_mode"] is True, payload
assert payload["service_active_state"] == "active", payload
assert payload["service_enabled"] in {"enabled", "enabled-runtime"}, payload
assert payload["running"] is True, payload
assert payload["api_ready"] is True, payload
assert payload["api_summary_total"] >= 1000, payload
print(payload["pid"])
PY
)"

http_output="$(python3 - "$port" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

port = int(sys.argv[1])
base = f"http://127.0.0.1:{port}"

def request(method, path, payload=None):
    body = None
    headers = {}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=10) as response:
        return response.status, json.loads(response.read().decode("utf-8"))

list_status, list_payload = request("GET", "/tasks?limit=2")
summary_status, summary_payload = request("GET", "/tasks/summary")
first_id = list_payload["tasks"][0]["id"]
show_status, show_payload = request("GET", "/tasks/" + urllib.parse.quote(first_id))
create_status, create_payload = request(
    "POST",
    "/tasks",
    {
        "title": "Smoke panel task http service",
        "objective": "Smoke panel task http service objective",
        "type": "smoke-panel-task-http-service",
        "owner": "panel-http-service",
        "accept": ["panel http service create"],
        "canonical_session": "smoke-panel-task-http-service",
    },
)
task_id = create_payload["task"]["id"]
update_status, update_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/update",
    {
        "status": "running",
        "owner": "panel-http-service",
        "note": "panel http service update note",
    },
)
close_status, close_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/close",
    {
        "status": "done",
        "note": "panel http service close note",
        "owner": "panel-http-service",
    },
)

assert list_status == 200, list_status
assert summary_status == 200, summary_status
assert show_status == 200, show_status
assert create_status == 201, create_status
assert update_status == 200, update_status
assert close_status == 200, close_status

assert list_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert summary_payload["inventory"]["total"] >= 1000
assert show_payload["task"]["id"] == first_id
assert create_payload["task"]["status"] == "todo"
assert update_payload["task"]["status"] == "running"
assert close_payload["task"]["status"] == "done"

print("SMOKE_TASK_PANEL_HTTP_SERVICE_HTTP_OK")
print(f"TASK_PANEL_HTTP_SERVICE_FIRST_ID {first_id}")
print(f"TASK_PANEL_HTTP_SERVICE_CREATED_ID {task_id}")
print("TASK_PANEL_HTTP_SERVICE_SUMMARY " + json.dumps(summary_payload["inventory"], ensure_ascii=True))
print("TASK_PANEL_HTTP_SERVICE_CLOSE " + json.dumps({"status": close_payload["task"]["status"], "closure_note": close_payload["task"]["closure_note"]}, ensure_ascii=True))
PY
)"

printf '%s\n' "$http_output"
task_id="$(printf '%s\n' "$http_output" | awk '/^TASK_PANEL_HTTP_SERVICE_CREATED_ID / {print $2}' | tail -n 1)"

python3 ./scripts/task_panel_http_ctl.py restart \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_panel_http_ctl.py healthcheck \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 ./scripts/task_panel_http_ctl.py status \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --json >"$status_json"

second_pid="$(python3 - "$status_json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["service_active_state"] == "active", payload
assert payload["running"] is True, payload
assert payload["api_ready"] is True, payload
print(payload["pid"])
PY
)"

python3 ./scripts/task_panel_http_ctl.py logs \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" \
  --lines 200 >"$logs_txt"

python3 ./scripts/task_panel_http_ctl.py stop \
  --service \
  --service-name "$service_name" \
  --service-unit-path "$service_unit_path" \
  --host 127.0.0.1 \
  --port "$port" >/dev/null

python3 - "$TASKS_DIR/$task_id.json" "$service_name" "$service_unit_path" "$first_pid" "$second_pid" "$logs_txt" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

task_path = pathlib.Path(sys.argv[1])
service_name = sys.argv[2]
service_unit_path = pathlib.Path(sys.argv[3])
first_pid = int(sys.argv[4])
second_pid = int(sys.argv[5])
logs_path = pathlib.Path(sys.argv[6])

task = json.loads(task_path.read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert task["source_channel"] == "panel", task["source_channel"]
assert task["owner"] == "panel-http-service", task["owner"]
assert task["closure_note"] == "panel http service close note", task["closure_note"]

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

assert first_pid > 0, first_pid
assert second_pid > 0, second_pid
assert first_pid != second_pid, (first_pid, second_pid)

for pid in (first_pid, second_pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pass
    else:
        raise AssertionError(f"task panel http pid still alive: {pid}")

logs_text = logs_path.read_text(encoding="utf-8")
assert "TASK_PANEL_HTTP_SERVICE_PREFLIGHT_OK" in logs_text, logs_text
assert "TASK_PANEL_HTTP_SERVER_OK" in logs_text, logs_text
assert service_unit_path.exists(), service_unit_path

print("SMOKE_TASK_PANEL_HTTP_SERVICE_OK")
print(f"TASK_PANEL_HTTP_SERVICE_FIRST_PID {first_pid}")
print(f"TASK_PANEL_HTTP_SERVICE_SECOND_PID {second_pid}")
print(f"TASK_PANEL_HTTP_SERVICE_FINAL_STATUS {task['status']}")
PY
