#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_delivery_summary.sh <task_id>
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

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
delivery = task.get("delivery") or {}
transitions = delivery.get("transitions") or []
claims = delivery.get("claim_history") or []
current_state = delivery.get("current_state") or "(none)"

print(f"task_id: {task.get('task_id', '')}")
print(f"task_status: {task.get('status', '')}")
print(f"delivery_state: {current_state}")
print("user_facing_ready: " + ("yes" if delivery.get("user_facing_ready") else "no"))
print(
    "minimum_user_facing_success_state: "
    + str(delivery.get("minimum_user_facing_success_state") or "visible")
)
print(f"transition_count: {len(transitions)}")
if transitions:
    last = transitions[-1]
    print(f"last_transition_state: {last.get('state', '')}")
    print(f"last_transition_timestamp: {last.get('timestamp', '')}")
    print(f"last_transition_actor: {last.get('actor', '')}")
    print(f"last_transition_channel: {last.get('channel', '')}")
print(f"user_facing_claim_count: {len(claims)}")
if claims:
    last_claim = claims[-1]
    print("last_user_facing_claim_allowed: " + ("yes" if last_claim.get("allowed") else "no"))
    print(f"last_user_facing_claim_state: {last_claim.get('current_state', '')}")
    print(f"last_user_facing_claim_required_state: {last_claim.get('required_state', '')}")

print("delivery_transition | timestamp | actor | channel | evidence")
for transition in transitions:
    print(
        f"{transition.get('state', '')} | {transition.get('timestamp', '')} | "
        f"{transition.get('actor', '')} | {transition.get('channel', '')} | {transition.get('evidence', '')}"
    )

if claims:
    print("user_facing_claim | allowed | timestamp | actor | channel | current_state | required_state | evidence")
    for claim in claims:
        print(
            f"{claim.get('claim', '')} | "
            + ("yes" if claim.get("allowed") else "no")
            + f" | {claim.get('timestamp', '')} | {claim.get('actor', '')} | {claim.get('channel', '')} | "
            f"{claim.get('current_state', '')} | {claim.get('required_state', '')} | {claim.get('evidence', '')}"
        )
PY
