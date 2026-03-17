#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
SCREENSHOT_HELPER="${GOLEM_SCREENSHOT_HELPER:-$HOME/.codex/skills/screenshot/scripts/take_screenshot.py}"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_capture_host_screenshot.sh <task_id> <target_kind> <target_ref|-> <actor> <evidence> [output_hint] [--json]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
target_kind="${2:-}"
target_ref_raw="${3:-}"
actor="${4:-}"
evidence="${5:-}"
shift 5 || true

output_hint=""
output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      if [ -n "$output_hint" ]; then
        usage
        fatal "argumento no soportado: $1"
      fi
      output_hint="$1"
      ;;
  esac
  shift
done

if [ -z "$task_id" ] || [ -z "$target_kind" ] || [ -z "$target_ref_raw" ] || [ -z "$actor" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, target_kind, target_ref, actor o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

if [ ! -f "$SCREENSHOT_HELPER" ]; then
  fatal "no existe el helper de screenshot: $SCREENSHOT_HELPER"
fi

resolution_json="$(./scripts/resolve_host_screenshot_destination.sh "$task_id" "$target_kind" "${output_hint:-}" --json)"
resolved_path="$(python3 - "$resolution_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("normalized_path", ""))
PY
)"

requested_at="$(date -u --iso-8601=seconds)"
target_ref="$target_ref_raw"
if [ "$target_ref" = "-" ]; then
  target_ref=""
fi

capture_state=""
capture_reason=""
capture_output=""
capture_exit="0"
capture_cmd_display=""

if [ "${GOLEM_HOST_SCREENSHOT_SIMULATE_BLOCKED:-0}" = "1" ]; then
  capture_state="blocked"
  capture_reason="host screenshot capture was blocked by a controlled verification fixture"
  capture_output="GOLEM_HOST_SCREENSHOT_SIMULATE_BLOCKED=1"
  capture_exit="2"
elif [ ! -f "$SCREENSHOT_HELPER" ]; then
  capture_state="blocked"
  capture_reason="host screenshot helper is not available in the current environment"
  capture_output="missing helper"
  capture_exit="2"
else
  cmd=(python3 "$SCREENSHOT_HELPER" --path "$resolved_path")
  case "$target_kind" in
    desktop-root)
      capture_cmd_display="python3 $SCREENSHOT_HELPER --path '$resolved_path'"
      ;;
    active-window)
      cmd+=(--active-window)
      capture_cmd_display="python3 $SCREENSHOT_HELPER --path '$resolved_path' --active-window"
      ;;
    region)
      if [ -z "$target_ref" ]; then
        capture_state="blocked"
        capture_reason="region capture requires an explicit x,y,w,h target_ref"
        capture_output="missing region target_ref"
        capture_exit="2"
      else
        cmd+=(--region "$target_ref")
        capture_cmd_display="python3 $SCREENSHOT_HELPER --path '$resolved_path' --region '$target_ref'"
      fi
      ;;
    window-id)
      if [ -z "$target_ref" ]; then
        capture_state="blocked"
        capture_reason="window-id capture requires an explicit target_ref"
        capture_output="missing window-id target_ref"
        capture_exit="2"
      else
        cmd+=(--window-id "$target_ref")
        capture_cmd_display="python3 $SCREENSHOT_HELPER --path '$resolved_path' --window-id '$target_ref'"
      fi
      ;;
    explicit-path-context)
      capture_cmd_display="python3 $SCREENSHOT_HELPER --path '$resolved_path'"
      ;;
    *)
      capture_state="blocked"
      capture_reason="target_kind is not capturable through the canonical host screenshot lane"
      capture_output="unsupported target_kind=$target_kind"
      capture_exit="2"
      ;;
  esac

  if [ -z "$capture_state" ]; then
    set +e
    capture_output="$("${cmd[@]}" 2>&1)"
    capture_exit="$?"
    set -e
    if [ "$capture_exit" -eq 0 ]; then
      capture_state="captured"
      capture_reason="host screenshot artifact was materialized and is awaiting verification"
    else
      capture_state="blocked"
      capture_reason="host screenshot capture did not complete in the current environment"
    fi
  fi
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-host-screenshot-capture.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$tmp_path" "$resolution_json" "$target_kind" "$target_ref_raw" "$actor" "$evidence" "$requested_at" "$capture_state" "$capture_reason" "$capture_output" "$capture_exit" "$capture_cmd_display" <<'PY'
import datetime
import hashlib
import json
import mimetypes
import os
import pathlib
import pwd
import sys

task_path = pathlib.Path(sys.argv[1])
tmp_path = pathlib.Path(sys.argv[2])
resolution = json.loads(sys.argv[3])
target_kind, target_ref_raw, actor, evidence, requested_at = sys.argv[4:9]
capture_state, capture_reason, capture_output, capture_exit, capture_cmd_display = sys.argv[9:14]

task = json.loads(task_path.read_text(encoding="utf-8"))
screenshot = task.setdefault("screenshot", {})
screenshot.setdefault("protocol_version", "1.0")
screenshot["required"] = True
screenshot.setdefault("current_state", "none")
screenshot.setdefault("ready_for_claim", False)
screenshot.setdefault("items", [])
screenshot.setdefault("events", [])
screenshot.setdefault("last_transition_at", "")
screenshot.setdefault("last_verified_at", "")
screenshot.setdefault("block_reason", "")
screenshot.setdefault("fail_reason", "")

capture_path = pathlib.Path(resolution.get("normalized_path", "")).expanduser()
exists = capture_path.exists()
readable = os.access(capture_path, os.R_OK) if exists else False
is_file = capture_path.is_file() if exists else False
owner = ""
owner_reliable = False
try:
    if exists:
        owner = pwd.getpwuid(capture_path.stat().st_uid).pw_name
        owner_reliable = True
except Exception:
    owner = ""
    owner_reliable = False
size_bytes = capture_path.stat().st_size if exists and is_file else 0
mime_type = mimetypes.guess_type(capture_path.name)[0] or "application/octet-stream"
sha256 = ""
if exists and readable and is_file:
    digest = hashlib.sha256()
    with capture_path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest()

state = capture_state
reason = capture_reason
captured_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
if capture_state == "captured" and (not exists or not readable or not is_file or size_bytes <= 0):
    state = "failed"
    reason = "screenshot command returned success but no readable non-empty file was materialized"

item_id = f"screenshot-{len(screenshot.get('items') or []) + 1:04d}"
item = {
    "item_id": item_id,
    "target_kind": target_kind,
    "target_ref": "" if target_ref_raw == "-" else target_ref_raw,
    "requested_path": resolution.get("requested_path", ""),
    "resolved_path": resolution.get("resolved_path", ""),
    "normalized_path": resolution.get("normalized_path", ""),
    "sha256": sha256,
    "size_bytes": size_bytes,
    "mime_type": mime_type,
    "owner": owner,
    "owner_reliable": owner_reliable,
    "exists": exists,
    "readable": readable,
    "requested_at": requested_at,
    "captured_at": captured_at,
    "verified_at": "",
    "evidence": evidence,
    "state": state,
    "capture_reason": reason,
    "capture_output": capture_output,
    "capture_exit_code": int(capture_exit),
    "capture_command": capture_cmd_display,
}

screenshot["items"].append(item)
screenshot["current_state"] = state
screenshot["ready_for_claim"] = False
screenshot["last_transition_at"] = captured_at
if state == "blocked":
    screenshot["block_reason"] = reason
    screenshot["fail_reason"] = ""
elif state == "failed":
    screenshot["fail_reason"] = reason
    screenshot["block_reason"] = ""
else:
    screenshot["block_reason"] = ""
    screenshot["fail_reason"] = ""
screenshot["events"].append(
    {
        "timestamp": captured_at,
        "actor": actor,
        "action": "capture",
        "reason": reason,
        "item_id": item_id,
        "evidence": evidence,
    }
)

task.setdefault("outputs", []).append(
    {
        "kind": "host-screenshot-capture",
        "captured_at": captured_at,
        "exit_code": 0 if state == "captured" else (2 if state == "blocked" else 1),
        "content": f"TASK_HOST_SCREENSHOT_{state.upper()} {task.get('task_id', '')} item_id={item_id}",
        "item_id": item_id,
        "target_kind": target_kind,
        "normalized_path": resolution.get("normalized_path", ""),
        "sha256": sha256,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "screenshot_state": state,
        "reason": reason,
    }
)
if state == "captured":
    task.setdefault("artifacts", []).append(
        {
            "name": f"host-screenshot-{item_id}",
            "path": resolution.get("normalized_path", ""),
            "kind": "host-screenshot",
            "captured_at": captured_at,
            "mime_type": mime_type,
            "size_bytes": size_bytes,
            "sha256": sha256,
        }
    )
task.setdefault("notes", []).append(f"host screenshot {state} recorded for target {target_kind}")
task["updated_at"] = captured_at

tmp_path.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

mv "$tmp_path" "$task_path"
trap - EXIT

item_json="$(python3 - "$task_path" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(json.dumps((task.get("screenshot") or {}).get("items", [])[-1], ensure_ascii=True))
PY
)"
item_state="$(python3 - "$item_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("state", ""))
PY
)"
item_id="$(python3 - "$item_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("item_id", ""))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$item_json"
else
  printf 'TASK_HOST_SCREENSHOT_%s %s item_id=%s\n' "$(printf '%s' "$item_state" | tr '[:lower:]' '[:upper:]')" "$task_id" "$item_id"
fi

case "$item_state" in
  captured) exit 0 ;;
  blocked) exit 2 ;;
  *) exit 1 ;;
esac
