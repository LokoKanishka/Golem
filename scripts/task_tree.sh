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
    extras = []
    if "step_order" in task:
        extras.append(f"step_order={task.get('step_order')}")
    if task.get("step_name"):
        extras.append(f"step_name={task.get('step_name')}")
    if "critical" in task:
        extras.append(f"critical={'yes' if task.get('critical') else 'no'}")
    if task.get("execution_mode"):
        extras.append(f"execution_mode={task.get('execution_mode')}")
    extra_suffix = ""
    if extras:
        extra_suffix = " | " + " | ".join(extras)
    return "{task_id} | {status} | {type} | {title}{extra_suffix}".format(
        task_id=task.get("task_id", "?"),
        status=task.get("status", "?"),
        type=task.get("type", "?"),
        title=task.get("title", ""),
        extra_suffix=extra_suffix,
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
