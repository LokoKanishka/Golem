#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_spawn_child.sh <parent_task_id> <type> <title>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

parent_task_id="${1:-}"
task_type="${2:-}"

if [ -z "$parent_task_id" ] || [ -z "$task_type" ] || [ "$#" -lt 3 ]; then
  usage
  fatal "faltan parent_task_id, type o title"
fi

title="${*:3}"
parent_path="$TASKS_DIR/${parent_task_id}.json"

if [ ! -f "$parent_path" ]; then
  fatal "no existe la tarea padre: $parent_task_id"
fi

cd "$REPO_ROOT"

created_output="$(
  TASK_PARENT_TASK_ID="$parent_task_id" \
  TASK_DEPENDS_ON="[\"$parent_task_id\"]" \
  ./scripts/task_new.sh "$task_type" "$title"
)"

child_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
if [ -z "$child_path" ]; then
  fatal "no se pudo extraer la ruta de la child task"
fi

printf 'TASK_CHILD_CREATED %s\n' "$child_path"
