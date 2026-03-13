#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_worker_summary.sh <task_id>
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

handoff = task.get("handoff") or {}
notes = task.get("notes", [])
artifacts = task.get("artifacts", [])
outputs = task.get("outputs", [])
worker_outputs = [output for output in outputs if output.get("kind") == "worker-result"]
last_worker = worker_outputs[-1] if worker_outputs else {}
last_note = notes[-1] if notes else "(none)"

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"status: {task.get('status', '?')}")
print(f"delegated_to: {handoff.get('delegated_to', '(none)')}")
print(f"worker_result_status: {last_worker.get('status', '(none)')}")
print(f"worker_result_summary: {last_worker.get('summary', '(none)')}")
print(f"artifacts: {len(artifacts)}")
print(f"last_note: {last_note}")
PY
