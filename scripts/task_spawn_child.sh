#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_spawn_child.sh <parent_task_id> <type> <title>

Opcional por entorno:
  TASK_CHILD_DEPENDS_ON='["task-a"]'
  TASK_CHILD_OBJECTIVE="objetivo explicito"
  TASK_CHILD_STEP_NAME="nombre-del-step"
  TASK_CHILD_STEP_ORDER=<numero>
  TASK_CHILD_CRITICAL=true|false
  TASK_CHILD_EXECUTION_MODE=local|worker
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

child_depends_on="${TASK_CHILD_DEPENDS_ON:-[\"$parent_task_id\"]}"

created_output="$(
  TASK_PARENT_TASK_ID="$parent_task_id" \
  TASK_DEPENDS_ON="$child_depends_on" \
  TASK_STEP_NAME="${TASK_CHILD_STEP_NAME:-}" \
  TASK_STEP_ORDER="${TASK_CHILD_STEP_ORDER:-}" \
  TASK_CRITICAL="${TASK_CHILD_CRITICAL:-}" \
  TASK_EXECUTION_MODE="${TASK_CHILD_EXECUTION_MODE:-}" \
  ./scripts/task_create.sh \
    "$title" \
    "${TASK_CHILD_OBJECTIVE:-$title}" \
    --type "$task_type" \
    --owner system \
    --source script
)"

child_path="$(printf '%s\n' "$created_output" | tail -n 1)"
if [ -z "$child_path" ]; then
  fatal "no se pudo extraer la ruta de la child task"
fi

printf 'TASK_CHILD_CREATED %s\n' "$child_path"
