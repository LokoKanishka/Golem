#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
summary_out="$tmpdir/summary.txt"
list_out="$tmpdir/list.txt"
show_out="$tmpdir/show.txt"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
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

python3 ./scripts/task_whatsapp_query.py --base-url "$base_url" --text "tasks summary" >"$summary_out"
python3 ./scripts/task_whatsapp_query.py --base-url "$base_url" --text "tasks list limit 2" >"$list_out"

first_task_id="$(python3 - "$port" <<'PY'
import json
import sys
import urllib.request

port = int(sys.argv[1])
with urllib.request.urlopen(f"http://127.0.0.1:{port}/tasks?limit=1", timeout=5) as response:
    payload = json.loads(response.read().decode("utf-8"))
print(payload["tasks"][0]["id"])
PY
)"

python3 ./scripts/task_whatsapp_query.py --base-url "$base_url" --text "task show ${first_task_id}" >"$show_out"

python3 - "$summary_out" "$list_out" "$show_out" "$first_task_id" <<'PY'
import pathlib
import sys

summary_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
list_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
show_text = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
first_task_id = sys.argv[4]

assert "TASKS SUMMARY" in summary_text, summary_text
assert "total:" in summary_text, summary_text
assert "- done:" in summary_text or "- todo:" in summary_text, summary_text

assert "TASKS LIST" in list_text, list_text
assert "returned: 2" in list_text, list_text
assert first_task_id in list_text, list_text

assert "TASK DETAIL" in show_text, show_text
assert f"id: {first_task_id}" in show_text, show_text
assert "status:" in show_text, show_text
assert "source_channel:" in show_text, show_text

print("SMOKE_WHATSAPP_TASK_QUERY_OK")
print(f"WHATSAPP_QUERY_FIRST_ID {first_task_id}")
PY
