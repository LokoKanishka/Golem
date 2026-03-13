#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_tree.sh <task_id>
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
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

python3 - "$TASKS_DIR" "$task_id" <<'PY'
import json
import pathlib
import sys

tasks_dir = pathlib.Path(sys.argv[1])
task_id = sys.argv[2]

def load_task(path: pathlib.Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)

current_path = tasks_dir / f"{task_id}.json"
current = load_task(current_path)

tasks = []
for path in sorted(tasks_dir.glob("*.json")):
    if path.is_file():
        tasks.append(load_task(path))

def describe(task):
    return "{task_id} | {status} | {type} | {title}".format(
        task_id=task.get("task_id", "?"),
        status=task.get("status", "?"),
        type=task.get("type", "?"),
        title=task.get("title", ""),
    )

parent_task_id = current.get("parent_task_id") or ""
parent = next((task for task in tasks if task.get("task_id") == parent_task_id), None)
children = [task for task in tasks if (task.get("parent_task_id") or "") == task_id]
depends_on = current.get("depends_on") or []

print(f"TASK_TREE {task_id}")
print("parent:")
if parent is None:
    print("- (none)")
else:
    print(f"- {describe(parent)}")

print("current:")
print(f"- {describe(current)}")

print("depends_on:")
if not depends_on:
    print("- (none)")
else:
    for dependency in depends_on:
        print(f"- {dependency}")

print("children:")
if not children:
    print("- (none)")
else:
    for child in children:
        print(f"- {describe(child)}")
PY
