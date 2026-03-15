#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_close.sh <task_id> <status> [note]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
status="${2:-}"
note="${3:-}"

if [ -z "$task_id" ] || [ -z "$status" ]; then
  usage
  fatal "faltan task_id o status"
fi

case "$status" in
  done|failed|blocked|delegated|cancelled) ;;
  *)
    fatal "status de cierre inválido: $status"
    ;;
esac

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-close.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$status" "$note" > "$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
status = sys.argv[2]
note = sys.argv[3]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task["status"] = status
task["updated_at"] = now

if note:
    task.setdefault("notes", []).append(note)

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_CLOSED %s %s\n' "$task_id" "$status"
