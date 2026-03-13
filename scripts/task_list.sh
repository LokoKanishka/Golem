#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

if [ ! -d "$TASKS_DIR" ]; then
  printf 'No tasks found.\n'
  exit 0
fi

python3 - "$TASKS_DIR" <<'PY'
import json
import pathlib
import sys

tasks_dir = pathlib.Path(sys.argv[1])
task_files = sorted(
    [path for path in tasks_dir.glob("*.json") if path.is_file()],
    key=lambda path: path.name,
)

if not task_files:
    print("No tasks found.")
    raise SystemExit(0)

for path in task_files:
    with path.open(encoding="utf-8") as fh:
        task = json.load(fh)
    print(
        "{task_id} | {status} | {type} | {title}".format(
            task_id=task.get("task_id", path.stem),
            status=task.get("status", "?"),
            type=task.get("type", "?"),
            title=task.get("title", ""),
        )
    )
PY
