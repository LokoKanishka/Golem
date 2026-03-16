#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_record_delivery_transition.sh <task_id> <state> <actor> <channel> <evidence>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
state="${2:-}"
actor="${3:-}"
channel="${4:-}"
evidence="${5:-}"

if [ -z "$task_id" ] || [ -z "$state" ] || [ -z "$actor" ] || [ -z "$channel" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, state, actor, channel o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-delivery-transition.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$state" "$actor" "$channel" "$evidence" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
state, actor, channel, evidence = sys.argv[2:6]

ordered_states = ["submitted", "accepted", "delivered", "visible", "verified_by_user"]
if state not in ordered_states:
    raise SystemExit(
        "ERROR: state invalido. Usar uno de: accepted, delivered, submitted, verified_by_user, visible"
    )

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

delivery = task.setdefault(
    "delivery",
    {
        "protocol_version": "1.0",
        "minimum_user_facing_success_state": "visible",
        "current_state": "",
        "user_facing_ready": False,
        "transitions": [],
        "claim_history": [],
    },
)
delivery.setdefault("protocol_version", "1.0")
delivery.setdefault("minimum_user_facing_success_state", "visible")
delivery.setdefault("current_state", "")
delivery.setdefault("user_facing_ready", False)
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])

current_state = delivery.get("current_state") or ""
if current_state == state:
    raise SystemExit(f"ERROR: la tarea ya esta en delivery state {state}")

if current_state:
    current_index = ordered_states.index(current_state)
    expected_state = ordered_states[current_index + 1] if current_index + 1 < len(ordered_states) else ""
    if state != expected_state:
        raise SystemExit(
            f"ERROR: transicion delivery invalida: {current_state} -> {state}; se esperaba {expected_state or 'ninguna mas'}"
        )
else:
    if state != "submitted":
        raise SystemExit("ERROR: la primera transicion delivery debe ser submitted")

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
transition = {
    "state": state,
    "timestamp": now,
    "actor": actor,
    "channel": channel,
    "evidence": evidence,
}

delivery["current_state"] = state
delivery["user_facing_ready"] = ordered_states.index(state) >= ordered_states.index(
    delivery.get("minimum_user_facing_success_state", "visible")
)
delivery["transitions"].append(transition)
delivery["last_transition_at"] = now
delivery["last_transition_actor"] = actor
delivery["last_transition_channel"] = channel
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_DELIVERY_RECORDED %s %s\n' "$task_id" "$state"
