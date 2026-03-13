#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_summary.sh <task_id>
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

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

notes = task.get("notes", [])
last_note = notes[-1] if notes else "(none)"

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"type: {task.get('type', '?')}")
print(f"status: {task.get('status', '?')}")
print(f"title: {task.get('title', '')}")
print(f"outputs: {len(task.get('outputs', []))}")
print(f"artifacts: {len(task.get('artifacts', []))}")
print(f"last_note: {last_note}")
PY
