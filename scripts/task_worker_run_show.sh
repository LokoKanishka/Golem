#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_worker_run_show.sh <task_id>
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

worker_run = task.get("worker_run") or {}
notes = task.get("notes", [])
last_note = notes[-1] if notes else "(none)"

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"status: {task.get('status', '?')}")
print(f"worker_runner: {worker_run.get('runner', '(none)')}")
print(f"worker_state: {worker_run.get('state', '(none)')}")
print(f"worker_result_status: {worker_run.get('result_status', '(none)')}")
print(f"decision_source: {worker_run.get('decision_source', '(none)')}")
print(f"sandbox_mode: {worker_run.get('sandbox_mode', '(none)')}")
print(f"ticket_path: {worker_run.get('ticket_path', '(none)')}")
print(f"log_path: {worker_run.get('log_path', '(none)')}")
print(f"last_message_path: {worker_run.get('last_message_path', '(none)')}")
print(f"exit_code: {worker_run.get('exit_code', '(none)')}")
print(f"artifacts: {len(task.get('artifacts', []))}")
print(f"latest_worker_note: {last_note}")
PY
