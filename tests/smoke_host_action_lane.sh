#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Golem Host Action Smoke $$"
command_ok="host-action-command-ok-$$"
dialog_pid=""
window_id=""

cleanup() {
  if [[ -n "$window_id" ]]; then
    wmctrl -i -c "$window_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$dialog_pid" ]] && kill -0 "$dialog_pid" 2>/dev/null; then
    kill "$dialog_pid" 2>/dev/null || true
    wait "$dialog_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

open_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh open --label xmessage-dialog -- \
    xmessage -title "$title" "Host action smoke" --json
)"

wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$title" --timeout 10 --json
)"

window_meta="$(python3 - "$open_json" "$wait_json" <<'PY'
import json
import sys
open_payload = json.loads(sys.argv[1])
wait_payload = json.loads(sys.argv[2])
print(open_payload["pid"])
print(wait_payload["window"]["window_id"])
PY
)"
dialog_pid="$(printf '%s\n' "$window_meta" | sed -n '1p')"
window_id="$(printf '%s\n' "$window_meta" | sed -n '2p')"

focus_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh focus --title "$title" --json
)"

command_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh command --label host-command -- bash -lc "printf '$command_ok'" --json
)"

python3 - "$open_json" "$wait_json" "$focus_json" "$command_json" "$title" "$command_ok" "$dialog_pid" <<'PY'
import json
import pathlib
import sys

open_payload = json.loads(sys.argv[1])
wait_payload = json.loads(sys.argv[2])
focus_payload = json.loads(sys.argv[3])
command_payload = json.loads(sys.argv[4])
title = sys.argv[5]
command_ok = sys.argv[6]
dialog_pid = sys.argv[7]

assert open_payload["action"] == "open"
assert wait_payload["action"] == "wait-window"
assert focus_payload["action"] == "focus"
assert command_payload["action"] == "command"

assert wait_payload["window"]["title"] == title
assert focus_payload["window_id"] == wait_payload["window"]["window_id"]
assert command_payload["exit_code"] == 0
assert command_payload["stdout_excerpt"].strip() == command_ok

for payload in (open_payload, wait_payload, focus_payload, command_payload):
    summary = pathlib.Path(payload["artifacts"]["summary"])
    assert summary.exists(), summary
    assert summary.stat().st_size > 0, summary

print("SMOKE_HOST_ACTION_LANE_OK")
print(f"HOST_ACTION_WINDOW {title}")
print(f"HOST_ACTION_DIALOG_PID {dialog_pid}")
print(f"HOST_ACTION_COMMAND_RUN {command_payload['run_dir']}")
PY
