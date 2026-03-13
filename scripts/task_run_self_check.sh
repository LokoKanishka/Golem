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

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    TASK_OUTPUT_EXTRA_JSON="$(
      python3 - "$self_check_state" <<'PY'
import json
import sys

print(json.dumps({
    "command": "./scripts/self_check.sh",
    "estado_general": sys.argv[1],
}))
PY
    )" ./scripts/task_add_output.sh "$task_id" "self-check" "$self_check_exit" "$self_check_output" >/dev/null 2>&1 || true
    ./scripts/task_close.sh "$task_id" failed "task_run_self_check aborted before completion" >/dev/null 2>&1 || true
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

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$self_check_state" <<'PY'
import json
import sys

print(json.dumps({
    "command": "./scripts/self_check.sh",
    "estado_general": sys.argv[1],
}))
PY
)" ./scripts/task_add_output.sh "$task_id" "self-check" "$self_check_exit" "$self_check_output"

if [ "$self_check_exit" -eq 0 ] && [ "$self_check_state" != "FAIL" ]; then
  ./scripts/task_close.sh "$task_id" done "self-check completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

./scripts/task_close.sh "$task_id" failed "self-check finished with failure state"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
