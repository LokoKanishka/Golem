#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

task_id=""
task_path=""
finalized="0"
self_check_output=""
self_check_exit="1"
self_check_state="UNKNOWN"
cleanup_files=()

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_run_self_check.sh "<title>"
USAGE
}

cleanup() {
  local file
  for file in "${cleanup_files[@]}"; do
    rm -f "$file"
  done
}

register_cleanup() {
  cleanup_files+=("$1")
}

finalize_task_json() {
  local final_status="$1"
  local note_message="$2"
  local tmp_path

  if [ -z "$task_path" ] || [ ! -f "$task_path" ]; then
    return 0
  fi

  tmp_path="$(mktemp "$TASKS_DIR/.task-run.XXXXXX.tmp")"
  register_cleanup "$tmp_path"

  SELF_CHECK_OUTPUT="$self_check_output" \
  SELF_CHECK_EXIT="$self_check_exit" \
  SELF_CHECK_STATE="$self_check_state" \
  FINAL_STATUS="$final_status" \
  NOTE_MESSAGE="$note_message" \
  python3 - "$task_path" > "$tmp_path" <<'PY'
import datetime
import json
import os
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
final_status = os.environ["FINAL_STATUS"]
note_message = os.environ["NOTE_MESSAGE"]
self_check_output = os.environ.get("SELF_CHECK_OUTPUT", "")
self_check_exit = int(os.environ.get("SELF_CHECK_EXIT", "1"))
self_check_state = os.environ.get("SELF_CHECK_STATE", "UNKNOWN")

task["status"] = final_status
task["updated_at"] = now

outputs = task.setdefault("outputs", [])
outputs.append(
    {
        "kind": "self-check",
        "captured_at": now,
        "command": "./scripts/self_check.sh",
        "exit_code": self_check_exit,
        "estado_general": self_check_state,
        "content": self_check_output,
    }
)

notes = task.setdefault("notes", [])
if note_message:
    notes.append(note_message)

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

  mv "$tmp_path" "$task_path"
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    finalize_task_json "failed" "task_run_self_check aborted before completion"
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

extract_task_id() {
  local created_output="$1"
  local created_path

  created_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
  if [ -z "$created_path" ]; then
    printf 'ERROR: no se pudo extraer la ruta de la tarea creada\n' >&2
    exit 1
  fi

  basename "$created_path" .json
}

title="${1:-}"
if [ -z "$title" ]; then
  usage
  printf 'ERROR: falta title\n' >&2
  exit 1
fi

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR"

created_output="$(./scripts/task_new.sh self-check "$title")"
printf '%s\n' "$created_output"

task_id="$(extract_task_id "$created_output")"
task_path="$TASKS_DIR/${task_id}.json"

running_output="$(./scripts/task_update.sh "$task_id" running)"
printf '%s\n' "$running_output"

set +e
self_check_output="$(./scripts/self_check.sh 2>&1)"
self_check_exit="$?"
set -e

printf '%s\n' "$self_check_output"

self_check_state="$(printf '%s\n' "$self_check_output" | sed -n 's/^estado_general: //p' | tail -n 1)"
if [ -z "$self_check_state" ]; then
  self_check_state="UNKNOWN"
fi

if [ "$self_check_exit" -eq 0 ] && [ "$self_check_state" != "FAIL" ]; then
  finalize_task_json "done" "self-check completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

finalize_task_json "failed" "self-check finished with failure state"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
