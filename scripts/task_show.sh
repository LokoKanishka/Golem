#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  echo "Usage: ./scripts/task_show.sh <task-id|path>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

INPUT="$1"

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

python3 - "$TARGET" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open(encoding="utf-8") as fh:
    data = json.load(fh)

print(json.dumps(data, ensure_ascii=False, indent=2))
PY
