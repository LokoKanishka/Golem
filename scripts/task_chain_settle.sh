#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_settle.sh <root_task_id|worker_task_id> [<done|failed|blocked> <summary> [--artifact <path> ...]]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
result_status="${2:-}"
result_summary="${3:-}"

if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

if [ -n "$result_status" ] && [ -z "$result_summary" ]; then
  usage
  fatal "si pasas status de settlement, tambien hace falta summary"
fi

case "$result_status" in
  ""|done|failed|blocked) ;;
  *)
    fatal "status invalido para settlement: $result_status"
    ;;
esac

shift $(( $# >= 3 ? 3 : $# ))

artifacts=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --artifact)
      if [ "$#" -lt 2 ]; then
        fatal "falta path despues de --artifact"
      fi
      artifacts+=("$2")
      shift 2
      ;;
    *)
      fatal "argumento no reconocido: $1"
      ;;
  esac
done

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

resolve_env="$(
  python3 - "$task_path" "$TASKS_DIR" <<'PY'
import json
import pathlib
import shlex
import sys


def load(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


task_path = pathlib.Path(sys.argv[1])
tasks_dir = pathlib.Path(sys.argv[2])
task = load(task_path)
task_id = task.get("task_id", task_path.stem)
task_type = task.get("type", "")

all_tasks = {}
for path in tasks_dir.glob("*.json"):
    all_tasks[path.stem] = load(path)

input_kind = "unknown"
root = None
child = None
await_steps = []
limitation = ""
ambiguous_result_target = ""

if task_type == "task-chain":
    input_kind = "root"
    root = task
elif task.get("parent_task_id"):
    input_kind = "child"
    root = all_tasks.get(task.get("parent_task_id", ""))
    child = task

if not isinstance(root, dict) or root.get("type") != "task-chain":
    limitation = "el input no resuelve a una root task-chain"
    root = {}

root_task_id = root.get("task_id", "")
root_status = root.get("status", "")
root_chain_status = root.get("chain_status", "")
chain_type = root.get("chain_type", "")
root_title = root.get("title", "")
chain_plan = root.get("chain_plan") if isinstance(root.get("chain_plan"), dict) else {}
steps = chain_plan.get("steps") if isinstance(chain_plan.get("steps"), list) else []

if root and steps:
    for step in steps:
        if not step.get("await_worker_result"):
            continue
        step_child_id = step.get("child_task_id", "")
        step_child = all_tasks.get(step_child_id, {}) if step_child_id else {}
        if not step_child and step.get("step_name"):
            for candidate in all_tasks.values():
                if candidate.get("parent_task_id") != root_task_id:
                    continue
                if candidate.get("step_name") == step.get("step_name"):
                    step_child = candidate
                    step_child_id = candidate.get("task_id", "")
                    break
        worker_result = latest_worker_result_output(step_child) if step_child else {}
        worker_result_status = worker_result.get("status") or (step_child.get("worker_run") or {}).get("result_status", "")
        await_steps.append({
            "step_name": step.get("step_name", ""),
            "step_status": step.get("status", ""),
            "step_order": step.get("step_order", ""),
            "critical": bool(step.get("critical", False)),
            "child_task_id": step_child_id,
            "child_status": step_child.get("status", ""),
            "worker_result_status": worker_result_status,
            "result_registered": bool(worker_result_status),
        })

if root and not child and await_steps:
    unresolved_children = [
        step for step in await_steps
        if step.get("child_status") in {"delegated", "worker_running", "running", ""}
        or not step.get("result_registered")
    ]
    if len(unresolved_children) == 1:
        child = all_tasks.get(unresolved_children[0].get("child_task_id", ""), {})
    elif len(unresolved_children) > 1:
        ambiguous_result_target = "root input is ambiguous for direct result recording because multiple worker children are still unresolved"

child_task_id = child.get("task_id", "") if isinstance(child, dict) else ""
child_status = child.get("status", "") if isinstance(child, dict) else ""
worker_result = latest_worker_result_output(child) if isinstance(child, dict) else {}
worker_result_status = worker_result.get("status") or ((child.get("worker_run") or {}).get("result_status", "") if isinstance(child, dict) else "")
result_registered = bool(worker_result_status or child_status in {"done", "failed", "blocked", "cancelled"})
awaiting_child_ids = [step.get("child_task_id", "") for step in await_steps if step.get("child_task_id")]
ready_child_ids = [
    step.get("child_task_id", "")
    for step in await_steps
    if step.get("child_task_id") and step.get("result_registered")
]
pending_child_ids = [
    step.get("child_task_id", "")
    for step in await_steps
    if step.get("child_task_id") and not step.get("result_registered")
]

values = {
    "INPUT_KIND": input_kind,
    "ROOT_TASK_ID": root_task_id,
    "ROOT_STATUS": root_status,
    "ROOT_CHAIN_STATUS": root_chain_status,
    "ROOT_TITLE": root_title,
    "CHAIN_TYPE": chain_type,
    "CHILD_TASK_ID": child_task_id,
    "CHILD_STATUS": child_status,
    "WORKER_RESULT_STATUS": worker_result_status,
    "RESULT_REGISTERED": "1" if result_registered else "0",
    "LIMITATION": limitation,
    "AMBIGUOUS_RESULT_TARGET": ambiguous_result_target,
    "AWAITING_CHILD_IDS_JSON": json.dumps(awaiting_child_ids),
    "READY_CHILD_IDS_JSON": json.dumps(ready_child_ids),
    "PENDING_CHILD_IDS_JSON": json.dumps(pending_child_ids),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"
eval "$resolve_env"

[ -z "$LIMITATION" ] || fatal "$LIMITATION"
[ -n "$ROOT_TASK_ID" ] || fatal "no se pudo resolver una root task-chain"
[ "$CHAIN_TYPE" = "repo-analysis-worker-manual" ] || [ "$CHAIN_TYPE" = "repo-analysis-worker-manual-multi" ] || fatal "settlement actual solo soporta chains manuales con worker awaitable"

./scripts/validate_chain_plan.sh "$ROOT_TASK_ID"

if [ -n "$result_status" ] && [ -n "$AMBIGUOUS_RESULT_TARGET" ] && [ "$INPUT_KIND" = "root" ]; then
  fatal "$AMBIGUOUS_RESULT_TARGET"
fi

if [ -n "$result_status" ] && [ -z "$CHILD_TASK_ID" ]; then
  fatal "no se encontro una child worker objetivo para registrar el resultado"
fi

recorded_now="false"
if [ -n "$result_status" ] && [ "$RESULT_REGISTERED" != "1" ]; then
  record_args=("$CHILD_TASK_ID" "$result_status" "$result_summary")
  for artifact in "${artifacts[@]}"; do
    record_args+=(--artifact "$artifact")
  done
  ./scripts/task_record_worker_result.sh "${record_args[@]}"
  recorded_now="true"
  resolve_env="$(
    python3 - "$TASKS_DIR/${ROOT_TASK_ID}.json" "$TASKS_DIR/${CHILD_TASK_ID}.json" <<'PY'
import json
import pathlib
import shlex
import sys


def load(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


root = load(pathlib.Path(sys.argv[1]))
child = load(pathlib.Path(sys.argv[2]))
worker_result = latest_worker_result_output(child)
values = {
    "ROOT_STATUS": root.get("status", ""),
    "ROOT_CHAIN_STATUS": root.get("chain_status", ""),
    "CHILD_STATUS": child.get("status", ""),
    "WORKER_RESULT_STATUS": worker_result.get("status") or (child.get("worker_run") or {}).get("result_status", ""),
    "RESULT_REGISTERED": "1",
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
  )"
  eval "$resolve_env"
fi

settlement_note=""
settlement_exit=0

if [ "$ROOT_STATUS" = "delegated" ] && [ "$ROOT_CHAIN_STATUS" = "awaiting_worker_result" ]; then
  ready_count="$(python3 - "$READY_CHILD_IDS_JSON" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
  )"
  pending_count="$(python3 - "$PENDING_CHILD_IDS_JSON" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
  )"

  if [ "$ready_count" -eq 0 ] && [ "$pending_count" -gt 0 ]; then
    settlement_note="worker results still pending for one or more awaitable children"
    settlement_exit=3
  else
    set +e
    resume_output="$(./scripts/task_chain_resume.sh "$ROOT_TASK_ID" 2>&1)"
    resume_exit="$?"
    set -e
    printf '%s\n' "$resume_output"
    settlement_note="awaitable workers reconciled for root=${ROOT_TASK_ID}; resume_exit=${resume_exit}"
    settlement_exit="$resume_exit"
  fi
else
  settlement_note="root already settled with status=${ROOT_STATUS} chain_status=${ROOT_CHAIN_STATUS}"
  settlement_exit=0
fi

root_status_snapshot="$(
  python3 - "$TASKS_DIR/${ROOT_TASK_ID}.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(task.get("status", ""))
print(task.get("chain_status", ""))
PY
)"
ROOT_STATUS="$(printf '%s\n' "$root_status_snapshot" | sed -n '1p')"
ROOT_CHAIN_STATUS="$(printf '%s\n' "$root_status_snapshot" | sed -n '2p')"

extra_json="$(
  python3 - "$TASKS_DIR/${ROOT_TASK_ID}.json" "$task_id" "$INPUT_KIND" "$CHILD_TASK_ID" "$WORKER_RESULT_STATUS" "$recorded_now" "$ROOT_STATUS" "$ROOT_CHAIN_STATUS" "$settlement_exit" "$READY_CHILD_IDS_JSON" "$PENDING_CHILD_IDS_JSON" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
input_task_id, input_kind, child_task_id, worker_result_status, recorded_now, root_status, root_chain_status, settlement_exit, ready_child_ids_json, pending_child_ids_json = sys.argv[2:12]
chain_summary = task.get("chain_summary") if isinstance(task.get("chain_summary"), dict) else {}
print(json.dumps({
    "input_task_id": input_task_id,
    "input_kind": input_kind,
    "worker_child_task_id": child_task_id,
    "worker_result_status": worker_result_status,
    "recorded_worker_result_now": recorded_now == "true",
    "root_status": root_status,
    "root_chain_status": root_chain_status,
    "ready_worker_child_ids": json.loads(ready_child_ids_json),
    "pending_worker_child_ids": json.loads(pending_child_ids_json),
    "dependency_barrier_states": [
        f"{barrier.get('group_name', '')}={barrier.get('status', '')}"
        for barrier in (chain_summary.get("dependency_barriers") or [])
        if barrier.get("group_name")
    ],
    "settlement_exit_code": int(settlement_exit),
}))
PY
)"
TASK_OUTPUT_EXTRA_JSON="$extra_json" ./scripts/task_add_output.sh "$ROOT_TASK_ID" "chain-settlement" "$settlement_exit" "$settlement_note" >/dev/null

case "$settlement_exit" in
  0)
    printf 'TASK_CHAIN_SETTLED %s %s\n' "$ROOT_TASK_ID" "$ROOT_STATUS"
    ;;
  1)
    printf 'TASK_CHAIN_SETTLED_FAIL %s\n' "$ROOT_TASK_ID"
    ;;
  2)
    printf 'TASK_CHAIN_SETTLED_BLOCKED %s\n' "$ROOT_TASK_ID"
    ;;
  3)
    printf 'TASK_CHAIN_SETTLE_WAITING %s\n' "$ROOT_TASK_ID"
    ;;
  *)
    printf 'TASK_CHAIN_SETTLE_UNKNOWN %s exit_code=%s\n' "$ROOT_TASK_ID" "$settlement_exit"
    ;;
esac

exit "$settlement_exit"
