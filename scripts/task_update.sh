#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_update.sh <task_id> <status>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
new_status="${2:-}"

if [ -z "$task_id" ] || [ -z "$new_status" ]; then
  usage
  fatal "faltan task_id o status"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-update.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$new_status" > "$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
new_status = sys.argv[2]
valid_statuses = {"queued", "running", "delegated", "worker_running", "done", "failed", "cancelled"}

if new_status not in valid_statuses:
    print(
        "ERROR: status invalido. Usar uno de: cancelled, delegated, done, failed, queued, running, worker_running",
        file=sys.stderr,
    )
    raise SystemExit(1)

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["status"] = new_status
task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_UPDATED %s %s\n' "$task_id" "$new_status"
