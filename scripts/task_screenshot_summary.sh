#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_screenshot_summary.sh <task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
screenshot = task.get("screenshot") or {}
items = screenshot.get("items") or []
events = screenshot.get("events") or []
last_item = items[-1] if items else {}

print(f"task_id: {task.get('task_id', '')}")
print(f"task_status: {task.get('status', '')}")
print("screenshot_required: " + ("yes" if screenshot.get("required") else "no"))
print(f"screenshot_state: {screenshot.get('current_state', 'none')}")
print("screenshot_ready_for_claim: " + ("yes" if screenshot.get("ready_for_claim") else "no"))
print(f"screenshot_item_count: {len(items)}")
print(f"screenshot_event_count: {len(events)}")
print(f"screenshot_last_block_reason: {screenshot.get('block_reason', '') or '(none)'}")
print(f"screenshot_last_fail_reason: {screenshot.get('fail_reason', '') or '(none)'}")
if last_item:
    print(f"screenshot_last_path: {last_item.get('normalized_path', '(none)')}")
    print(f"screenshot_last_sha256: {last_item.get('sha256', '(none)')}")
if items:
    print(
        "item_id | state | target_kind | target_ref | normalized_path | mime_type | size_bytes | sha256 | owner | exists | readable | requested_at | captured_at | verified_at"
    )
    for item in items:
        print(
            f"{item.get('item_id', '')} | {item.get('state', '')} | {item.get('target_kind', '')} | "
            f"{item.get('target_ref', '')} | {item.get('normalized_path', '')} | {item.get('mime_type', '')} | "
            f"{item.get('size_bytes', '')} | {item.get('sha256', '')} | {item.get('owner', '')} | "
            f"{item.get('exists', '')} | {item.get('readable', '')} | {item.get('requested_at', '')} | "
            f"{item.get('captured_at', '')} | {item.get('verified_at', '')}"
        )
if events:
    print("event | timestamp | actor | action | reason | item_id | evidence")
    for event in events:
        print(
            f"{event.get('action', '')} | {event.get('timestamp', '')} | {event.get('actor', '')} | "
            f"{event.get('action', '')} | {event.get('reason', '')} | {event.get('item_id', '')} | {event.get('evidence', '')}"
        )
PY
