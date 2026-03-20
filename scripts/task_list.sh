#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
STATUS_FILTER=""

usage() {
  echo "Usage: ./scripts/task_list.sh [--status <todo|running|blocked|done|failed|canceled>]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)
      [[ $# -ge 2 ]] || usage
      STATUS_FILTER="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ ! -d "$TASKS_DIR" ]; then
  printf 'ID\tSTATUS\tOWNER\tSOURCE\tTITLE\n'
  exit 0
fi

TASKS_DIR="$TASKS_DIR" STATUS_FILTER="$STATUS_FILTER" python3 - <<'PY'
import json
import os
import pathlib
import sys

tasks_dir = pathlib.Path(os.environ["TASKS_DIR"])
status_filter = os.environ["STATUS_FILTER"]
task_files = sorted(
    [path for path in tasks_dir.glob("*.json") if path.is_file()],
    key=lambda path: path.name,
)

print("ID\tSTATUS\tOWNER\tSOURCE\tTITLE")

for path in task_files:
    try:
        with path.open(encoding="utf-8") as fh:
            task = json.load(fh)
    except json.JSONDecodeError as exc:
        print(f"WARN: skipping invalid task file {path.name}: {exc}", file=sys.stderr)
        continue
    task_id = task.get("id") or task.get("task_id") or path.stem
    status = task.get("status", "")
    if status_filter and status != status_filter:
        continue
    owner = task.get("owner", "")
    source = task.get("source_channel") or task.get("origin", "")
    title = task.get("title", "")
    print(
        f"{task_id}\t{status}\t{owner}\t{source}\t{title}"
    )
PY
