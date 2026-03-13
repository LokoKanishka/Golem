#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_add_artifact.sh <task_id> <kind> <path>

Opcional:
  TASK_ARTIFACT_EXTRA_JSON='{"foo":"bar"}' ./scripts/task_add_artifact.sh ...
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
kind="${2:-}"
artifact_path="${3:-}"

if [ -z "$task_id" ] || [ -z "$kind" ] || [ -z "$artifact_path" ]; then
  usage
  fatal "faltan task_id, kind o path"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-add-artifact.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

TASK_ARTIFACT_EXTRA_JSON="${TASK_ARTIFACT_EXTRA_JSON:-}" \
python3 - "$task_path" "$kind" "$artifact_path" > "$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys
import os

task_path = pathlib.Path(sys.argv[1])
kind = sys.argv[2]
artifact_path = sys.argv[3]
extra_raw = os.environ.get("TASK_ARTIFACT_EXTRA_JSON", "")

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

extra = {}
if extra_raw:
    extra = json.loads(extra_raw)
    if not isinstance(extra, dict):
        raise SystemExit("TASK_ARTIFACT_EXTRA_JSON debe ser un objeto JSON")

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
artifact_entry = {
    "path": artifact_path,
    "kind": kind,
    "created_at": now,
}
artifact_entry.update(extra)

task.setdefault("artifacts", []).append(artifact_entry)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_ARTIFACT_ADDED %s %s %s\n' "$task_id" "$kind" "$artifact_path"
