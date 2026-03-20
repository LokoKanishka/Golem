#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_add_artifact.sh <task-id|path> <artifact-path> [--actor <actor>] [--note <note>]

Compatibility:
./scripts/task_add_artifact.sh <task_id> <kind> <path>

Legacy optional:
TASK_ARTIFACT_EXTRA_JSON='{"foo":"bar"}' ./scripts/task_add_artifact.sh ...
USAGE
  exit 1
}

[[ $# -ge 2 ]] || usage

INPUT="$1"
shift

LEGACY_KIND=""
ARTIFACT_PATH=""
ACTOR=""
NOTE="Artifact added."

if [[ $# -ge 2 && "$2" != --* ]]; then
  LEGACY_KIND="$1"
  ARTIFACT_PATH="$2"
  shift 2
else
  ARTIFACT_PATH="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || usage
      NOTE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$ARTIFACT_PATH" ]] || { echo "Artifact path is required." >&2; exit 2; }

if [[ -f "$INPUT" ]]; then
  TARGET="$INPUT"
elif [[ -f "$TASKS_DIR/$INPUT.json" ]]; then
  TARGET="$TASKS_DIR/$INPUT.json"
elif [[ -f "$TASKS_DIR/$INPUT" ]]; then
  TARGET="$TASKS_DIR/$INPUT"
else
  echo "Task not found: $INPUT" >&2
  exit 2
fi

TASK_TARGET="$TARGET" \
ARTIFACT_PATH="$ARTIFACT_PATH" \
LEGACY_KIND="$LEGACY_KIND" \
ACTOR="$ACTOR" \
NOTE="$NOTE" \
TASK_ARTIFACT_EXTRA_JSON="${TASK_ARTIFACT_EXTRA_JSON:-}" \
python3 - <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys

task_path = pathlib.Path(os.environ["TASK_TARGET"])
artifact_path = os.environ["ARTIFACT_PATH"]
legacy_kind = os.environ["LEGACY_KIND"]
actor_override = os.environ["ACTOR"]
note = os.environ["NOTE"]
extra_raw = os.environ.get("TASK_ARTIFACT_EXTRA_JSON", "")

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

extra = {}
if extra_raw:
    extra = json.loads(extra_raw)
    if not isinstance(extra, dict):
        raise SystemExit("TASK_ARTIFACT_EXTRA_JSON debe ser un objeto JSON")

if not isinstance(task.get("artifacts"), list):
    task["artifacts"] = []
if not isinstance(task.get("history"), list):
    task["history"] = []

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")

is_canonical = "id" in task

if is_canonical and not legacy_kind:
    if artifact_path not in task["artifacts"]:
        task["artifacts"].append(artifact_path)
else:
    artifact_entry = {
        "path": artifact_path,
        "kind": legacy_kind or "artifact",
        "created_at": iso_now,
    }
    artifact_entry.update(extra)
    task["artifacts"].append(artifact_entry)

task["updated_at"] = iso_now
actor = actor_override or task.get("owner") or "operator"
task["history"].append(
    {
        "at": iso_now,
        "actor": actor,
        "action": "artifact_added",
        "note": f"{note} path={artifact_path}",
    }
)

identifier = task.get("id") or task.get("task_id") or task_path.stem

with task_path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, indent=2, ensure_ascii=False)
    fh.write("\n")

print(f"TASK_ARTIFACT_ADDED {identifier}")
print(task_path)
PY
