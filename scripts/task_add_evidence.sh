#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_add_evidence.sh <task-id|path> --type <type> --note <note> [--path <path>] [--command <command>] [--result <result>] [--actor <actor>]
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

INPUT="$1"
shift

TYPE=""
NOTE=""
EVIDENCE_PATH=""
COMMAND=""
RESULT=""
ACTOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      [[ $# -ge 2 ]] || usage
      TYPE="$2"
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || usage
      NOTE="$2"
      shift 2
      ;;
    --path)
      [[ $# -ge 2 ]] || usage
      EVIDENCE_PATH="$2"
      shift 2
      ;;
    --command)
      [[ $# -ge 2 ]] || usage
      COMMAND="$2"
      shift 2
      ;;
    --result)
      [[ $# -ge 2 ]] || usage
      RESULT="$2"
      shift 2
      ;;
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$TYPE" ]] || { echo "Evidence type is required." >&2; exit 2; }
[[ -n "$NOTE" ]] || { echo "Evidence note is required." >&2; exit 2; }

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
TYPE="$TYPE" \
NOTE="$NOTE" \
EVIDENCE_PATH="$EVIDENCE_PATH" \
COMMAND="$COMMAND" \
RESULT="$RESULT" \
ACTOR="$ACTOR" \
python3 - <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys

path = pathlib.Path(os.environ["TASK_TARGET"])
etype = os.environ["TYPE"]
note = os.environ["NOTE"]
epath = os.environ["EVIDENCE_PATH"]
command = os.environ["COMMAND"]
result = os.environ["RESULT"]
actor_override = os.environ["ACTOR"]

with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

if not isinstance(data.get("evidence"), list):
    data["evidence"] = []
if not isinstance(data.get("history"), list):
    data["history"] = []

entry = {
    "type": etype,
    "note": note,
}
if epath:
    entry["path"] = epath
if command:
    entry["command"] = command
if result:
    entry["result"] = result

data["evidence"].append(entry)

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")
data["updated_at"] = iso_now

actor = actor_override or data.get("owner") or "operator"
data["history"].append(
    {
        "at": iso_now,
        "actor": actor,
        "action": "evidence_added",
        "note": f"Evidence added: type={etype}. {note}",
    }
)

identifier = data.get("id") or data.get("task_id") or path.stem

with path.open("w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

print(f"TASK_EVIDENCE_ADDED {identifier}")
print(path)
PY
