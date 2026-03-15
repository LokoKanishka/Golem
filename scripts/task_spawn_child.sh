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
  TASK_OBJECTIVE="${TASK_CHILD_OBJECTIVE:-}" \
  TASK_STEP_NAME="${TASK_CHILD_STEP_NAME:-}" \
  TASK_STEP_ORDER="${TASK_CHILD_STEP_ORDER:-}" \
  TASK_CRITICAL="${TASK_CHILD_CRITICAL:-}" \
  TASK_EXECUTION_MODE="${TASK_CHILD_EXECUTION_MODE:-}" \
  ./scripts/task_new.sh "$task_type" "$title"
)"

child_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
if [ -z "$child_path" ]; then
  fatal "no se pudo extraer la ruta de la child task"
fi

child_abs_path="$REPO_ROOT/$child_path"
tmp_path="$(mktemp "$TASKS_DIR/.task-child-meta.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

TASK_CHILD_OBJECTIVE="${TASK_CHILD_OBJECTIVE:-}" \
TASK_CHILD_STEP_NAME="${TASK_CHILD_STEP_NAME:-}" \
TASK_CHILD_STEP_ORDER="${TASK_CHILD_STEP_ORDER:-}" \
TASK_CHILD_CRITICAL="${TASK_CHILD_CRITICAL:-}" \
TASK_CHILD_EXECUTION_MODE="${TASK_CHILD_EXECUTION_MODE:-}" \
python3 - "$child_abs_path" <<'PY' >"$tmp_path"
import datetime
import json
import os
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
objective = os.environ.get("TASK_CHILD_OBJECTIVE", "").strip()
step_name = os.environ.get("TASK_CHILD_STEP_NAME", "").strip()
step_order_raw = os.environ.get("TASK_CHILD_STEP_ORDER", "").strip()
critical_raw = os.environ.get("TASK_CHILD_CRITICAL", "").strip().lower()
execution_mode = os.environ.get("TASK_CHILD_EXECUTION_MODE", "").strip()

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

if objective:
    task["objective"] = objective
if step_name:
    task["step_name"] = step_name
if step_order_raw:
    task["step_order"] = int(step_order_raw)
if critical_raw:
    if critical_raw in {"1", "true", "yes", "y", "on"}:
        task["critical"] = True
    elif critical_raw in {"0", "false", "no", "n", "off"}:
        task["critical"] = False
    else:
        raise SystemExit("TASK_CHILD_CRITICAL debe ser true/false")
if execution_mode:
    task["execution_mode"] = execution_mode

task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$child_abs_path"
trap - EXIT

printf 'TASK_CHILD_CREATED %s\n' "$child_path"
