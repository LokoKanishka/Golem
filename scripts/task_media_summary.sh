#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_media_summary.sh <task_id>
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
media = task.get("media") or {}
items = media.get("items") or []
events = media.get("events") or []

print(f"task_id: {task.get('task_id', '')}")
print(f"task_status: {task.get('status', '')}")
print("media_required: " + ("yes" if media.get("required") else "no"))
print(f"media_state: {media.get('current_state', 'none')}")
print("media_ready: " + ("yes" if media.get("ready") else "no"))
print(f"media_item_count: {len(items)}")
print(f"media_event_count: {len(events)}")
if items:
    print(
        "item_id | state | source_kind | source_path | normalized_path | basename | extension | mime_type | size_bytes | sha256 | exists | readable | owner | collected_at | verified_at"
    )
    for item in items:
        print(
            f"{item.get('item_id', '')} | {item.get('current_state', '')} | {item.get('source_kind', '')} | "
            f"{item.get('source_path', '')} | {item.get('normalized_path', '')} | {item.get('basename', '')} | "
            f"{item.get('extension', '')} | {item.get('mime_type', '')} | {item.get('size_bytes', '')} | "
            f"{item.get('sha256', '')} | {item.get('exists', '')} | {item.get('readable', '')} | "
            f"{item.get('owner', '')} | {item.get('collected_at', '')} | {item.get('verified_at', '')}"
        )
if events:
    print("event | timestamp | actor | reason | item_id | evidence")
    for event in events:
        print(
            f"{event.get('action', '')} | {event.get('timestamp', '')} | {event.get('actor', '')} | "
            f"{event.get('reason', '')} | {event.get('item_id', '')} | {event.get('evidence', '')}"
        )
PY
