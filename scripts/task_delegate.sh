#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
DELEGATION_POLICY="$REPO_ROOT/config/delegation_policy.json"
WORKER_POLICY="$REPO_ROOT/config/worker_handoff_policy.json"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_delegate.sh <task_id>
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

if [ ! -f "$DELEGATION_POLICY" ]; then
  fatal "falta delegation policy: $DELEGATION_POLICY"
fi

if [ ! -f "$WORKER_POLICY" ]; then
  fatal "falta worker handoff policy: $WORKER_POLICY"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-delegate.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$DELEGATION_POLICY" "$WORKER_POLICY" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
delegation_policy_path = pathlib.Path(sys.argv[2])
worker_policy_path = pathlib.Path(sys.argv[3])

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)
with delegation_policy_path.open(encoding="utf-8") as fh:
    delegation_policy = json.load(fh)
with worker_policy_path.open(encoding="utf-8") as fh:
    worker_policy = json.load(fh)

task_type = task.get("type", "")
if not task_type:
    print("ERROR: la tarea no tiene type", file=sys.stderr)
    raise SystemExit(1)

if task.get("handoff"):
    print(f"ERROR: la tarea {task.get('task_id', task_path.stem)} ya tiene handoff", file=sys.stderr)
    raise SystemExit(1)

if task.get("status") in {"done", "failed", "cancelled"}:
    print(f"ERROR: la tarea {task.get('task_id', task_path.stem)} ya esta cerrada", file=sys.stderr)
    raise SystemExit(1)

delegation_rules = {
    rule.get("task_type"): rule
    for rule in delegation_policy.get("rules", [])
    if isinstance(rule, dict) and rule.get("task_type")
}
worker_rules = {
    rule.get("task_type"): rule
    for rule in worker_policy.get("rules", [])
    if isinstance(rule, dict) and rule.get("task_type")
}

delegation_rule = delegation_rules.get(task_type)
worker_rule = worker_rules.get(task_type)

if delegation_rule is not None and delegation_rule.get("owner") != "worker_future":
    owner = delegation_rule.get("owner", delegation_policy.get("default_owner", "review_required"))
    print(
        f"ERROR: task_type {task_type} pertenece a {owner} segun delegation policy y no debe delegarse a worker_future",
        file=sys.stderr,
    )
    raise SystemExit(1)

if worker_rule is None:
    print(f"ERROR: task_type {task_type} no esta definido en worker_handoff_policy", file=sys.stderr)
    raise SystemExit(1)

if not worker_rule.get("handoff_allowed", False):
    print(
        f"ERROR: task_type {task_type} no esta habilitado para handoff a worker_future",
        file=sys.stderr,
    )
    raise SystemExit(1)

required_fields = worker_rule.get("required_fields") or worker_policy.get("required_fields", [])
required_present = []
missing_required = []

for field in required_fields:
    value = task.get(field)
    present = value not in (None, "", [], {})
    if present:
        required_present.append(field)
    else:
        missing_required.append(field)

if missing_required:
    print(
        "ERROR: faltan campos requeridos para handoff: " + ", ".join(missing_required),
        file=sys.stderr,
    )
    raise SystemExit(1)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
new_status = worker_policy.get("status_on_handoff", "delegated")
note = f"delegated to worker_future on {now}"

handoff = {
    "delegated_to": worker_policy.get("default_handoff_owner", "worker_future"),
    "delegated_at": now,
    "task_type": task_type,
    "title": task.get("title", ""),
    "objective": task.get("objective", ""),
    "recommended_next_step": worker_rule.get("recommended_next_step", "prepare worker execution"),
    "required_fields_present": required_present,
    "missing_required_fields": missing_required,
    "policy_version": worker_policy.get("version", ""),
    "rationale": worker_rule.get("rationale", ""),
    "source_status": task.get("status", ""),
}

task["handoff"] = handoff
task["status"] = new_status
task["updated_at"] = now
task.setdefault("notes", []).append(note)

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_DELEGATED %s\n' "$task_id"
