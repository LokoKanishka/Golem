#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
SETTLE_SCRIPT="$REPO_ROOT/scripts/task_chain_settle.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_reconcile_pending.sh [--apply] [<root_task_id> ...]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

apply_mode="false"
root_filters=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply_mode="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      root_filters+=("$1")
      shift
      ;;
  esac
done

[ -d "$TASKS_DIR" ] || fatal "no existe tasks/"

inspection_json="$(
  python3 - "$TASKS_DIR" "${root_filters[@]}" <<'PY'
import json
import pathlib
import sys


def load(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


tasks_dir = pathlib.Path(sys.argv[1])
root_filters = set(sys.argv[2:])

all_tasks = {}
for path in tasks_dir.glob("*.json"):
    if not path.is_file():
        continue
    all_tasks[path.stem] = load(path)

results = []
for task_id, task in sorted(all_tasks.items()):
    if task.get("type") != "task-chain":
        continue
    if task.get("chain_type") not in {"repo-analysis-worker-manual", "repo-analysis-worker-manual-multi"}:
        continue
    if root_filters and task_id not in root_filters:
        continue

    chain_plan = task.get("chain_plan") if isinstance(task.get("chain_plan"), dict) else {}
    steps = chain_plan.get("steps") if isinstance(chain_plan.get("steps"), list) else []
    await_steps = [step for step in steps if step.get("await_worker_result")]
    if not await_steps:
        continue

    await_worker_children = []
    for worker_step in await_steps:
        worker_child_id = worker_step.get("child_task_id", "")
        worker_child = all_tasks.get(worker_child_id, {}) if worker_child_id else {}
        if not worker_child_id:
            for candidate in all_tasks.values():
                if candidate.get("parent_task_id") == task_id and candidate.get("step_name") == worker_step.get("step_name"):
                    worker_child = candidate
                    worker_child_id = candidate.get("task_id", "")
                    break

        worker_result = latest_worker_result_output(worker_child) if worker_child else {}
        worker_result_status = worker_result.get("status") or ((worker_child.get("worker_run") or {}).get("result_status", "") if worker_child else "")
        await_worker_children.append(
            {
                "step_name": worker_step.get("step_name", ""),
                "child_task_id": worker_child_id,
                "child_status": worker_child.get("status", "") if worker_child else "",
                "worker_result_status": worker_result_status,
                "result_registered": bool(worker_result_status),
            }
        )

    root_status = task.get("status", "")
    chain_status = task.get("chain_status", "")
    chain_summary = task.get("chain_summary") if isinstance(task.get("chain_summary"), dict) else {}
    ready_children = [
        child for child in await_worker_children
        if child["result_registered"] and child["child_status"] in {"done", "failed", "blocked", "cancelled"}
    ]
    pending_children = [
        child for child in await_worker_children
        if not child["result_registered"] or child["child_status"] in {"delegated", "worker_running", "running", ""}
    ]

    if root_status == "delegated" and chain_status == "awaiting_worker_result":
        if ready_children:
            decision = "ready_for_settlement"
        else:
            decision = "still_waiting"
    else:
        decision = "already_reconciled"

    results.append(
        {
            "root_id": task_id,
            "title": task.get("title", ""),
            "root_status": root_status,
            "chain_status": chain_status,
            "worker_child_ids": [child["child_task_id"] for child in await_worker_children if child["child_task_id"]],
            "ready_worker_child_ids": [child["child_task_id"] for child in ready_children if child["child_task_id"]],
            "pending_worker_child_ids": [child["child_task_id"] for child in pending_children if child["child_task_id"]],
            "dependency_barrier_states": [
                f"{barrier.get('group_name', '')}={barrier.get('status', '')}"
                for barrier in (chain_summary.get("dependency_barriers") or [])
                if barrier.get("group_name")
            ],
            "waiting_dependency_barrier_names": chain_summary.get("waiting_dependency_barrier_names", []),
            "worker_children": await_worker_children,
            "await_step_names": [step.get("step_name", "") for step in await_steps],
            "reconcile_decision": decision,
        }
    )

print(json.dumps(results))
PY
)"

count_total="$(python3 - "$inspection_json" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

if [ "$count_total" -eq 0 ]; then
  printf 'CHAIN_RECONCILE_NONE\n'
  exit 0
fi

printf 'mode: %s\n' "$([ "$apply_mode" = "true" ] && printf 'apply' || printf 'inspect')"
printf 'roots_considered: %s\n' "$count_total"
printf '\n'
printf 'root_id | worker_child_ids | ready_worker_child_ids | pending_worker_child_ids | dependency_barriers | current_status | chain_status | reconcile_decision | final_state_if_applied\n'

while IFS= read -r row_json; do
  [ -n "$row_json" ] || continue
  eval "$(
    python3 - "$row_json" <<'PY'
import json
import shlex
import sys

row = json.loads(sys.argv[1])
for key, value in row.items():
    print(f"{key.upper()}={shlex.quote(str(value))}")
PY
  )"

  final_state_if_applied="(none)"
  if [ "$apply_mode" = "true" ] && [ "$RECONCILE_DECISION" = "ready_for_settlement" ]; then
    set +e
    settle_output="$("$SETTLE_SCRIPT" "$ROOT_ID" 2>&1)"
    settle_exit="$?"
    set -e
    printf '%s\n' "$settle_output"
    final_state_if_applied="$(
      python3 - "$TASKS_DIR/${ROOT_ID}.json" "$settle_exit" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
exit_code = sys.argv[2]
print(f"status={task.get('status', '')} chain_status={task.get('chain_status', '')} settle_exit={exit_code}")
PY
    )"
  elif [ "$apply_mode" = "true" ] && [ "$RECONCILE_DECISION" = "still_waiting" ]; then
    final_state_if_applied="unchanged_waiting"
  elif [ "$apply_mode" = "true" ] && [ "$RECONCILE_DECISION" = "already_reconciled" ]; then
    final_state_if_applied="already_reconciled"
  fi

  printf '%s | %s | %s | %s | %s | %s | %s | %s | %s\n' \
    "$ROOT_ID" \
    "$(python3 - "$row_json" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
print(",".join(row.get("worker_child_ids", [])) or "(none)")
PY
)" \
    "$(python3 - "$row_json" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
print(",".join(row.get("ready_worker_child_ids", [])) or "(none)")
PY
)" \
    "$(python3 - "$row_json" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
print(",".join(row.get("pending_worker_child_ids", [])) or "(none)")
PY
)" \
    "$(python3 - "$row_json" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
print(",".join(row.get("dependency_barrier_states", [])) or "(none)")
PY
)" \
    "$ROOT_STATUS" \
    "$CHAIN_STATUS" \
    "$RECONCILE_DECISION" \
    "$final_state_if_applied"
done < <(
  python3 - "$inspection_json" <<'PY'
import json, sys
for row in json.loads(sys.argv[1]):
    print(json.dumps(row))
PY
)

printf '\n'
python3 - "$inspection_json" "$apply_mode" "$TASKS_DIR" <<'PY'
import json
import pathlib
import sys

rows = json.loads(sys.argv[1])
apply_mode = sys.argv[2] == "true"
tasks_dir = pathlib.Path(sys.argv[3])

summary = {"still_waiting": 0, "ready_for_settlement": 0, "already_reconciled": 0}
for row in rows:
    summary[row["reconcile_decision"]] = summary.get(row["reconcile_decision"], 0) + 1

print(f"still_waiting: {summary.get('still_waiting', 0)}")
print(f"ready_for_settlement: {summary.get('ready_for_settlement', 0)}")
print(f"already_reconciled: {summary.get('already_reconciled', 0)}")

if apply_mode:
    final_counts = {}
    for row in rows:
        task = json.loads((tasks_dir / f"{row['root_id']}.json").read_text(encoding="utf-8"))
        key = f"{task.get('status', '')}/{task.get('chain_status', '')}"
        final_counts[key] = final_counts.get(key, 0) + 1
    print("final_states_after_apply:")
    for key in sorted(final_counts):
        print(f"- {key}: {final_counts[key]}")
PY
