#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_PATH="$REPO_ROOT/config/delegation_policy.json"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/delegation_decide.sh task <task_id>
  ./scripts/delegation_decide.sh type <task_type>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

mode="${1:-}"
value="${2:-}"

if [ -z "$mode" ] || [ -z "$value" ]; then
  usage
  fatal "faltan modo o valor"
fi

if [ ! -f "$POLICY_PATH" ]; then
  fatal "no existe la policy: $POLICY_PATH"
fi

case "$mode" in
  task)
    task_path="$TASKS_DIR/${value}.json"
    if [ ! -f "$task_path" ]; then
      fatal "no existe la tarea: $value"
    fi
    python3 - "$POLICY_PATH" "$task_path" <<'PY'
import json
import pathlib
import sys

policy_path = pathlib.Path(sys.argv[1])
task_path = pathlib.Path(sys.argv[2])

policy = json.loads(policy_path.read_text(encoding="utf-8"))
task = json.loads(task_path.read_text(encoding="utf-8"))
task_type = task.get("type", "").strip()

rules = {rule["task_type"]: rule for rule in policy.get("rules", [])}
rule = rules.get(task_type)

if rule is None:
    print("owner: review_required")
    print(f"task_type: {task_type or '(missing)'}")
    print("rationale: task_type no definido en la policy actual")
    print("escalation: human review required")
    raise SystemExit(1)

print(f"owner: {rule['owner']}")
print(f"task_type: {task_type}")
print(f"rationale: {rule['rationale']}")
print(f"escalation: {rule['escalation']}")
PY
    ;;
  type)
    python3 - "$POLICY_PATH" "$value" <<'PY'
import json
import pathlib
import sys

policy_path = pathlib.Path(sys.argv[1])
task_type = sys.argv[2]

policy = json.loads(policy_path.read_text(encoding="utf-8"))
rules = {rule["task_type"]: rule for rule in policy.get("rules", [])}
rule = rules.get(task_type)

if rule is None:
    print("owner: review_required")
    print(f"task_type: {task_type}")
    print("rationale: task_type no definido en la policy actual")
    print("escalation: human review required")
    raise SystemExit(1)

print(f"owner: {rule['owner']}")
print(f"task_type: {task_type}")
print(f"rationale: {rule['rationale']}")
print(f"escalation: {rule['escalation']}")
PY
    ;;
  *)
    usage
    exit 1
    ;;
esac
