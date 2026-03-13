#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_finish_codex_run.sh <task_id> <status> <summary> [--artifact <path> ...]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
status="${2:-}"
summary="${3:-}"

if [ -z "$task_id" ] || [ -z "$status" ] || [ -z "$summary" ]; then
  usage
  fatal "faltan task_id, status o summary"
fi

shift 3

case "$status" in
  done|failed) ;;
  *)
    fatal "status invalido para finish_codex_run: $status"
    ;;
esac

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task_id = task.get("task_id", task_path.stem)
status = task.get("status")
worker_run = task.get("worker_run") or {}
worker_state = worker_run.get("state", "")
if status not in {"worker_running", "delegated"}:
    print(f"ERROR: la tarea {task_id} no esta en worker_running ni delegated", file=sys.stderr)
    raise SystemExit(1)
if status == "worker_running" and worker_state not in {"finished", "failed"}:
    print(f"ERROR: la tarea {task_id} aun no tiene una corrida worker terminada", file=sys.stderr)
    raise SystemExit(1)
PY

artifacts=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --artifact)
      if [ "$#" -lt 2 ]; then
        fatal "falta path despues de --artifact"
      fi
      artifacts+=("$2")
      shift 2
      ;;
    *)
      fatal "argumento no reconocido: $1"
      ;;
  esac
done

has_result_artifact="no"
for artifact in "${artifacts[@]}"; do
  case "$artifact" in
    *.run.result.md|handoffs/*.run.result.md)
      has_result_artifact="yes"
      ;;
  esac
done

if [ "$has_result_artifact" = "no" ]; then
  extract_output="$(./scripts/task_extract_worker_result.sh "$task_id" 2>/dev/null || true)"
  auto_artifact="$(printf '%s\n' "$extract_output" | sed -n 's/^WORKER_RESULT_EXTRACTED //p' | tail -n 1)"
  if [ -n "$auto_artifact" ]; then
    "$VALIDATE_MARKDOWN" "$REPO_ROOT/$auto_artifact" >/dev/null
    artifacts+=("$auto_artifact")
  fi
fi

tmp_task="$(mktemp "$TASKS_DIR/.task-worker-run-close.XXXXXX.tmp")"
trap 'rm -f "$tmp_task"' EXIT
python3 - "$task_path" "$status" "$summary" >"$tmp_task" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
finish_status = sys.argv[2]
summary = sys.argv[3]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.setdefault("worker_run", {})
worker_run["finish_status"] = finish_status
worker_run["finish_summary"] = summary
worker_run["result_status"] = finish_status
worker_run["closed_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task.setdefault("notes", []).append(f"controlled codex run finish requested with status={finish_status}")

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$task_path"
trap - EXIT

record_args=("$task_id" "$status" "$summary")
for artifact in "${artifacts[@]}"; do
  record_args+=(--artifact "$artifact")
done

./scripts/task_record_worker_result.sh "${record_args[@]}"
printf 'TASK_CODEX_RUN_FINISH_OK %s\n' "$task_id"
