#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
task_id=""
server_pid=""

cleanup() {
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
import json
import sys
import time
import urllib.error
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
        "title": "Smoke panel task http",
        "objective": "Smoke panel task http objective",
        "type": "smoke-panel-task-http",
        "owner": "system",
        "accept": ["panel http create"],
        "canonical_session": "smoke-panel-task-http",
    },
)
task_id = create_payload["task"]["id"]
update_status, update_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/update",
    {
        "status": "running",
        "owner": "panel-http",
        "note": "panel http update note",
    },
)
host_expect_status, host_expect_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/host-expectation",
    {
        "target_kind": "active-window",
        "require_summary": True,
        "min_artifact_count": 1,
        "note": "panel http host expectation note",
    },
)
host_refresh_status, host_refresh_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/host-verification/refresh",
    {
        "actor": "panel-http",
    },
)
close_status, close_payload = request(
    "POST",
    "/tasks/" + urllib.parse.quote(task_id) + "/close",
    {
        "status": "done",
        "note": "panel http close note",
        "owner": "panel-http",
    },
)

assert list_status == 200, list_status
assert summary_status == 200, summary_status
assert show_status == 200, show_status
assert create_status == 201, create_status
assert update_status == 200, update_status
assert host_expect_status == 200, host_expect_status
assert host_refresh_status == 200, host_refresh_status
assert close_status == 200, close_status

assert list_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert summary_payload["inventory"]["total"] >= 1000
assert show_payload["task"]["id"] == first_id

assert create_payload["task"]["status"] == "todo"
assert create_payload["task"]["source_channel"] == "panel"
assert "task_create.sh" in create_payload["meta"]["canonical_script_command"]

assert update_payload["task"]["status"] == "running"
assert update_payload["task"]["owner"] == "panel-http"
assert "task_update.sh" in update_payload["meta"]["canonical_script_command"]

assert host_expect_payload["task"]["host_expectation"]["present"] is True
assert host_expect_payload["task"]["host_expectation"]["target_kind"] == "active-window"
assert host_expect_payload["task"]["host_verification"]["status"] == "insufficient_evidence"
assert "task_set_host_expectation.sh" in host_expect_payload["meta"]["canonical_script_command"]

assert host_refresh_payload["task"]["host_verification"]["present"] is True
assert host_refresh_payload["task"]["host_verification"]["status"] == "insufficient_evidence"
assert "no host evidence attached" in host_refresh_payload["task"]["host_verification"]["reason"]
assert "task_refresh_host_verification.sh" in host_refresh_payload["meta"]["canonical_script_command"]

assert close_payload["task"]["status"] == "done"
assert close_payload["task"]["closure_note"] == "panel http close note"
assert "task_close.sh" in close_payload["meta"]["canonical_script_command"]

print("SMOKE_PANEL_TASK_HTTP_OK")
print(f"PANEL_HTTP_FIRST_ID {first_id}")
print(f"PANEL_HTTP_CREATED_ID {task_id}")
print("PANEL_HTTP_LIST " + json.dumps(list_payload["meta"], ensure_ascii=True))
print("PANEL_HTTP_SUMMARY " + json.dumps(summary_payload["inventory"], ensure_ascii=True))
print("PANEL_HTTP_CREATE " + json.dumps({"status": create_payload["task"]["status"], "source_channel": create_payload["task"]["source_channel"]}, ensure_ascii=True))
print("PANEL_HTTP_UPDATE " + json.dumps({"status": update_payload["task"]["status"], "owner": update_payload["task"]["owner"]}, ensure_ascii=True))
print("PANEL_HTTP_HOST_EXPECT " + json.dumps({"status": host_expect_payload["task"]["host_verification"]["status"], "target_kind": host_expect_payload["task"]["host_expectation"]["target_kind"]}, ensure_ascii=True))
print("PANEL_HTTP_HOST_REFRESH " + json.dumps({"status": host_refresh_payload["task"]["host_verification"]["status"], "reason": host_refresh_payload["task"]["host_verification"]["reason"]}, ensure_ascii=True))
print("PANEL_HTTP_CLOSE " + json.dumps({"status": close_payload["task"]["status"], "closure_note": close_payload["task"]["closure_note"]}, ensure_ascii=True))
PY
)"

printf '%s\n' "$http_output"
task_id="$(printf '%s\n' "$http_output" | awk '/^PANEL_HTTP_CREATED_ID / {print $2}' | tail -n 1)"
