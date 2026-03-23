#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
create_out="$tmpdir/create.txt"
update_out="$tmpdir/update.txt"
close_out="$tmpdir/close.txt"
server_pid=""
task_id=""

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

base_url="http://127.0.0.1:${port}"

python3 ./scripts/task_whatsapp_mutate.py --base-url "$base_url" --text \
  "task create title=Smoke WhatsApp task mutate ; objective=Validate WhatsApp mutation path ; type=smoke-whatsapp-task-mutate ; owner=whatsapp-operator ; accept=whatsapp mutate smoke create" \
  >"$create_out"

task_id="$(awk -F': ' '/^id: / {print $2}' "$create_out" | tail -n 1)"
[[ -n "$task_id" ]] || {
  echo "FAIL: no task id from WhatsApp create" >&2
  exit 1
}

python3 ./scripts/task_whatsapp_mutate.py --base-url "$base_url" --text \
  "task update ${task_id} status=running ; owner=whatsapp-operator ; title=Smoke WhatsApp task mutate updated ; objective=Validate WhatsApp mutation path updated ; note=whatsapp update applied ; append_accept=whatsapp mutate smoke update" \
  >"$update_out"

python3 ./scripts/task_whatsapp_mutate.py --base-url "$base_url" --text \
  "task close ${task_id} status=done ; note=whatsapp close applied ; owner=whatsapp-operator" \
  >"$close_out"

python3 - "$create_out" "$update_out" "$close_out" "$TASKS_DIR/$task_id.json" <<'PY'
import json
import pathlib
import sys

create_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
update_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
close_text = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
task = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))

assert "TASK CREATED" in create_text, create_text
assert f"id: {task['id']}" in create_text, create_text
assert "source_channel: whatsapp" in create_text, create_text

assert "TASK UPDATED" in update_text, update_text
assert f"id: {task['id']}" in update_text, update_text
assert "status: running" in update_text, update_text
assert "source_channel: whatsapp" in update_text, update_text

assert "TASK CLOSED" in close_text, close_text
assert f"id: {task['id']}" in close_text, close_text
assert "status: done" in close_text, close_text
assert "closure_note: whatsapp close applied" in close_text, close_text
assert "source_channel: whatsapp" in close_text, close_text

assert task["status"] == "done", task["status"]
assert task["source_channel"] == "whatsapp", task["source_channel"]
assert task["owner"] == "whatsapp-operator", task["owner"]
assert task["title"] == "Smoke WhatsApp task mutate updated", task["title"]
assert task["objective"] == "Validate WhatsApp mutation path updated", task["objective"]
assert task["closure_note"] == "whatsapp close applied", task["closure_note"]
assert task["notes"][-2:] == ["whatsapp update applied", "whatsapp close applied"], task["notes"]
assert task["acceptance_criteria"][-1] == "whatsapp mutate smoke update", task["acceptance_criteria"]
assert task["history"][0]["action"] == "created", task["history"][0]
assert task["history"][-2]["action"] == "status_changed", task["history"][-2]
assert task["history"][-2]["actor"] == "whatsapp", task["history"][-2]
assert task["history"][-1]["action"] == "closed_done", task["history"][-1]
assert task["history"][-1]["actor"] == "whatsapp", task["history"][-1]

print("SMOKE_WHATSAPP_TASK_MUTATE_OK")
print(f"WHATSAPP_TASK_MUTATE_ID {task['id']}")
print(f"WHATSAPP_TASK_MUTATE_FINAL_STATUS {task['status']}")
PY
