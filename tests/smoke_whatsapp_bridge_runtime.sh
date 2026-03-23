#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
bridge_audit="$tmpdir/bridge-audit.jsonl"
bridge_state="$tmpdir/bridge-state.json"
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

run_bridge_fixture() {
  local body="$1"
  local fixture="$tmpdir/fixture-$(date +%s%N).jsonl"
  python3 - "$fixture" "$body" <<'PY'
import json
import pathlib
import sys
import time

fixture = pathlib.Path(sys.argv[1])
body = sys.argv[2]
timestamp_ms = int(time.time() * 1000)
payload = {
    "type": "log",
    "time": "2026-03-23T07:30:00.000Z",
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
fixture.write_text(json.dumps(payload, ensure_ascii=True) + "\n", encoding="utf-8")
PY

  python3 ./scripts/task_whatsapp_bridge_runtime.py \
    --base-url "$base_url" \
    --state-file "$bridge_state" \
    --audit-file "$bridge_audit" \
    --replay-file "$fixture" \
    --send-dry-run >/dev/null
}

run_bridge_fixture "tasks summary"
run_bridge_fixture "tasks list limit 2"
run_bridge_fixture "task show task-20260313T003348Z-06ef71e3"
run_bridge_fixture "task create title=Smoke WhatsApp runtime bridge ; objective=Validate runtime WhatsApp bridge ; type=smoke-whatsapp-runtime-bridge ; owner=whatsapp-runtime ; accept=runtime bridge create"

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
  echo "FAIL: no task id from runtime bridge create" >&2
  exit 1
}

run_bridge_fixture "task update ${task_id} status=running ; owner=whatsapp-runtime ; title=Smoke WhatsApp runtime bridge updated ; objective=Validate runtime WhatsApp bridge updated ; note=runtime bridge update ; append_accept=runtime bridge update"
run_bridge_fixture "task close ${task_id} status=done ; note=runtime bridge close ; owner=whatsapp-runtime"

python3 - "$bridge_audit" "$TASKS_DIR/$task_id.json" <<'PY'
import json
import pathlib
import sys

audit_entries = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
task = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

handled = [entry for entry in audit_entries if entry.get("type") == "handled"]
ops = [entry.get("operation") for entry in handled]
assert ops == ["summary", "list", "show", "create", "update", "close"], ops

for entry in handled:
    delivery = entry["delivery"]
    assert delivery["returncode"] == 0, entry
    assert delivery["dry_run"] is True, entry
    parsed = delivery["parsed"]
    assert parsed["action"] == "send", parsed
    assert parsed["channel"] == "whatsapp", parsed
    assert parsed["dryRun"] is True, parsed
    assert parsed["payload"]["to"] == "+156348867", parsed

summary = handled[0]
assert "TASKS SUMMARY" in summary["response_text"], summary
assert "total: 1395" in summary["response_text"], summary

listing = handled[1]
assert "TASKS LIST" in listing["response_text"], listing
assert "returned: 2" in listing["response_text"], listing

show = handled[2]
assert "TASK DETAIL" in show["response_text"], show
assert "id: task-20260313T003348Z-06ef71e3" in show["response_text"], show

create = handled[3]
assert create["response_details"]["task_id"] == task["id"], create
assert "TASK CREATED" in create["response_text"], create

update = handled[4]
assert update["response_details"]["task_id"] == task["id"], update
assert "status: running" in update["response_text"], update

close = handled[5]
assert close["response_details"]["task_id"] == task["id"], close
assert "status: done" in close["response_text"], close
assert "closure_note: runtime bridge close" in close["response_text"], close

assert task["status"] == "done", task["status"]
assert task["source_channel"] == "whatsapp", task["source_channel"]
assert task["owner"] == "whatsapp-runtime", task["owner"]
assert task["closure_note"] == "runtime bridge close", task["closure_note"]
assert task["notes"][-2:] == ["runtime bridge update", "runtime bridge close"], task["notes"]

print("SMOKE_WHATSAPP_BRIDGE_RUNTIME_OK")
print(f"WHATSAPP_BRIDGE_RUNTIME_TASK_ID {task['id']}")
print(f"WHATSAPP_BRIDGE_RUNTIME_FINAL_STATUS {task['status']}")
print(f"WHATSAPP_BRIDGE_RUNTIME_HANDLED {len(handled)}")
PY
