#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_worker_preflight.sh <task_id>
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
[ -f "$task_path" ] || fatal "no existe la tarea: $task_id"

cd "$REPO_ROOT"

readarray -t task_meta < <(
  python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

print(task.get("status", ""))
print(task.get("type", ""))
print("yes" if isinstance(task.get("handoff"), dict) else "no")
worker_run = task.get("worker_run") or {}
print(worker_run.get("state", ""))
PY
)

task_status="${task_meta[0]:-}"
task_type="${task_meta[1]:-}"
handoff_present="${task_meta[2]:-no}"
worker_state="${task_meta[3]:-}"

case "$task_status" in
  done|failed|cancelled)
    fatal "la tarea $task_id ya esta cerrada con status $task_status"
    ;;
esac

if [ "$task_status" != "delegated" ]; then
  fatal "la tarea $task_id no esta en estado delegated"
fi

if [ "$handoff_present" != "yes" ]; then
  fatal "la tarea $task_id no tiene bloque handoff"
fi

case "$worker_state" in
  running|ready)
    fatal "la tarea $task_id ya tiene worker activo o en preparacion"
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  fatal "codex CLI no esta disponible"
fi

ticket_path="$HANDOFFS_DIR/${task_id}.codex.md"
if [ ! -f "$ticket_path" ]; then
  ./scripts/task_prepare_codex_ticket.sh "$task_id" >/dev/null
fi
[ -f "$ticket_path" ] || fatal "no existe ni pudo generarse el ticket Codex"

set +e
can_run_output="$(./scripts/task_worker_can_run.sh "$task_id")"
can_run_exit="$?"
set -e
if [ "$can_run_exit" -ne 0 ]; then
  printf '%s\n' "$can_run_output"
  fatal "worker_run_policy no permite corrida real para $task_id"
fi

printf 'task_exists: ok\n'
printf 'task_status: %s\n' "$task_status"
printf 'task_type: %s\n' "$task_type"
printf 'task_closed: no\n'
printf 'worker_state: %s\n' "${worker_state:-"(none)"}"
printf 'handoff: ok\n'
printf 'repo_root: %s\n' "$REPO_ROOT"
printf 'codex_cli: ok\n'
printf 'ticket_path: %s\n' "${ticket_path#$REPO_ROOT/}"
printf '%s\n' "$can_run_output"
printf 'decision: allowed\n'
printf 'WORKER_PREFLIGHT_OK %s\n' "$task_id"
