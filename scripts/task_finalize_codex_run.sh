#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_finalize_codex_run.sh <task_id> <done|failed>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
status="${2:-}"

if [ -z "$task_id" ] || [ -z "$status" ]; then
  usage
  fatal "faltan task_id o status"
fi

case "$status" in
  done|failed) ;;
  *)
    fatal "status invalido para finalize_codex_run: $status"
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

if status not in {"worker_running", "delegated", "failed"}:
    print(f"ERROR: la tarea {task_id} no esta en un estado finalizable de worker", file=sys.stderr)
    raise SystemExit(1)

if worker_state not in {"finished", "failed"}:
    print(f"ERROR: la tarea {task_id} no tiene worker_run.state finalizable", file=sys.stderr)
    raise SystemExit(1)
PY

artifact_rel="$(
  python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
repo_root = task_path.parent.parent.resolve()
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.get("worker_run") or {}
artifact_rel = worker_run.get("result_artifact_path", "")
if artifact_rel and (repo_root / artifact_rel).exists():
    print(artifact_rel)
PY
)"

if [ -z "$artifact_rel" ]; then
  extract_output="$(./scripts/task_extract_worker_result.sh "$task_id")"
  printf '%s\n' "$extract_output"
  artifact_rel="$(printf '%s\n' "$extract_output" | sed -n 's/^WORKER_RESULT_EXTRACTED //p' | tail -n 1)"
  [ -n "$artifact_rel" ] || fatal "no se pudo determinar el artifact extraido"
else
  printf 'WORKER_RESULT_EXTRACTED %s\n' "$artifact_rel"
fi

summary="$(
  python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.get("worker_run") or {}
extracted = (worker_run.get("extracted_summary") or "").strip()
if extracted:
    print(extracted[:600])
    raise SystemExit(0)

exit_code = worker_run.get("exit_code")
worker_state = worker_run.get("state", "(none)")
task_type = task.get("type", "(none)")
print(
    f"Automatic worker result extracted for {task_type} with worker_state={worker_state} "
    f"and exit_code={exit_code}; review artifact for the full response."
)
PY
)"

WORKER_RESULT_EXTRA_JSON="$(
  python3 - "$task_path" "$artifact_rel" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
artifact_rel = sys.argv[2]
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.get("worker_run") or {}
print(json.dumps({
    "source": "codex_auto_extract",
    "extracted_summary": worker_run.get("extracted_summary", ""),
    "result_artifact_path": artifact_rel,
    "result_source_files": worker_run.get("result_source_files", []),
}))
PY
)" ./scripts/task_finish_codex_run.sh "$task_id" "$status" "$summary" --artifact "$artifact_rel"

printf 'TASK_CODEX_RUN_FINALIZED %s\n' "$task_id"
