#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_record_worker_result.sh <task_id> <status> <summary> [--artifact <path> ...]
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
    fatal "status inválido para resultado worker: $status"
    ;;
esac

output_exit_code="1"
if [ "$status" = "done" ]; then
  output_exit_code="0"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

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

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task_id = task.get("task_id", task_path.stem)
if task.get("status") not in {"delegated", "worker_running"}:
    print(f"ERROR: la tarea {task_id} no esta en estado delegated ni worker_running", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(task.get("handoff"), dict):
    print(f"ERROR: la tarea {task_id} no tiene bloque handoff", file=sys.stderr)
    raise SystemExit(1)
PY

artifact_paths_json="$(
  python3 - "$REPO_ROOT" "${artifacts[@]}" <<'PY'
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
artifact_args = sys.argv[2:]
artifact_paths = []

for raw in artifact_args:
    path = pathlib.Path(raw)
    if not path.is_absolute():
        path = (repo_root / path).resolve()
    else:
        path = path.resolve()

    try:
        path.relative_to(repo_root)
    except ValueError:
        print(f"ERROR: artifact fuera del repo: {raw}", file=sys.stderr)
        raise SystemExit(1)

    if not path.exists():
        print(f"ERROR: artifact inexistente: {raw}", file=sys.stderr)
        raise SystemExit(1)

    artifact_paths.append(path.relative_to(repo_root).as_posix())

print(json.dumps(artifact_paths))
PY
)"

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$status" "$summary" "$artifact_paths_json" <<'PY'
import json
import sys

status, summary, artifact_paths_json = sys.argv[1:4]
artifact_paths = json.loads(artifact_paths_json)
print(json.dumps({
    "status": status,
    "summary": summary,
    "source": "codex_manual",
    "artifact_paths": artifact_paths,
}))
PY
)" ./scripts/task_add_output.sh "$task_id" "worker-result" "$output_exit_code" "$summary"

for artifact in "${artifacts[@]}"; do
  artifact_abs="$(
    python3 - "$REPO_ROOT" "$artifact" <<'PY'
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
path = pathlib.Path(sys.argv[2])
if not path.is_absolute():
    path = (repo_root / path).resolve()
else:
    path = path.resolve()
print(path)
PY
  )"

  case "$artifact_abs" in
    *.md)
      "$VALIDATE_MARKDOWN" "$artifact_abs" >/dev/null
      ;;
  esac
  artifact_rel="$(
    python3 - "$REPO_ROOT" "$artifact_abs" <<'PY'
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
path = pathlib.Path(sys.argv[2])
print(path.relative_to(repo_root).as_posix())
PY
  )"
  ./scripts/task_add_artifact.sh "$task_id" "worker-result" "$artifact_rel"
done

./scripts/task_close.sh "$task_id" "$status" "worker result recorded from codex"
printf 'TASK_WORKER_RESULT_OK %s\n' "$task_id"
