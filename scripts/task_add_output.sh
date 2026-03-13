#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_add_output.sh <task_id> <kind> <exit_code> <content>

Opcional:
  TASK_OUTPUT_EXTRA_JSON='{"command":"...","foo":"bar"}' ./scripts/task_add_output.sh ...
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
kind="${2:-}"
exit_code_raw="${3:-}"
content="${4:-}"

if [ -z "$task_id" ] || [ -z "$kind" ] || [ -z "$exit_code_raw" ]; then
  usage
  fatal "faltan task_id, kind o exit_code"
fi

if ! [[ "$exit_code_raw" =~ ^-?[0-9]+$ ]]; then
  fatal "exit_code inválido: $exit_code_raw"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-add-output.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

TASK_OUTPUT_EXTRA_JSON="${TASK_OUTPUT_EXTRA_JSON:-}" \
python3 - "$task_path" "$kind" "$exit_code_raw" "$content" > "$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys
import os

task_path = pathlib.Path(sys.argv[1])
kind = sys.argv[2]
exit_code = int(sys.argv[3])
content = sys.argv[4]
extra_raw = os.environ.get("TASK_OUTPUT_EXTRA_JSON", "")

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

extra = {}
if extra_raw:
    extra = json.loads(extra_raw)
    if not isinstance(extra, dict):
        raise SystemExit("TASK_OUTPUT_EXTRA_JSON debe ser un objeto JSON")

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
output_entry = {
    "kind": kind,
    "captured_at": now,
    "exit_code": exit_code,
    "content": content,
}
output_entry.update(extra)

task.setdefault("outputs", []).append(output_entry)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_OUTPUT_ADDED %s %s\n' "$task_id" "$kind"
