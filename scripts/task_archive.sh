#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
ARCHIVE_DIR="$TASKS_DIR/archive"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_archive.sh <task-id|path> [--actor <actor>] [--note <note>] [--force]
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

INPUT="$1"
shift

ACTOR=""
NOTE="Task archived."
FORCE=0

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
    --force)
      FORCE=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -f "$INPUT" ]]; then
  TARGET="$INPUT"
elif [[ -f "$TASKS_DIR/$INPUT.json" ]]; then
  TARGET="$TASKS_DIR/$INPUT.json"
elif [[ -f "$TASKS_DIR/$INPUT" ]]; then
  TARGET="$TASKS_DIR/$INPUT"
else
  echo "Task not found in active tasks: $INPUT" >&2
  exit 2
fi

case "$TARGET" in
  "$ARCHIVE_DIR"/*)
    echo "Task is already archived: $TARGET" >&2
    exit 2
    ;;
esac

mkdir -p "$ARCHIVE_DIR"

TASK_TARGET="$TARGET" ARCHIVE_DIR="$ARCHIVE_DIR" ACTOR="$ACTOR" NOTE="$NOTE" FORCE="$FORCE" python3 - <<'PY'
import datetime as dt
import json
import os
import pathlib

path = pathlib.Path(os.environ["TASK_TARGET"])
archive_dir = pathlib.Path(os.environ["ARCHIVE_DIR"])
actor_override = os.environ["ACTOR"]
note = os.environ["NOTE"]
force = os.environ["FORCE"] == "1"

with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

status = data.get("status", "")
archivable = {"done", "failed", "canceled", "blocked"}

if status not in archivable and not force:
    raise SystemExit(f"Refusing to archive non-terminal status={status}. Use --force if really needed.")

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")

if not isinstance(data.get("history"), list):
    data["history"] = []

data["updated_at"] = iso_now
actor = actor_override or data.get("owner") or "operator"
data["history"].append(
    {
        "at": iso_now,
        "actor": actor,
        "action": "archived",
        "note": note,
    }
)

dest = archive_dir / path.name
if dest.exists():
    raise SystemExit(f"Archive destination already exists: {dest}")

tmp = dest.with_suffix(dest.suffix + ".tmp")
with tmp.open("w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

tmp.replace(dest)
path.unlink()

identifier = data.get("id") or data.get("task_id") or path.stem
print(f"TASK_ARCHIVED {identifier} {status}")
print(dest)
PY
