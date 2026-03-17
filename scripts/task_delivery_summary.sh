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
visible_artifact_deliveries = delivery.get("visible_artifact_deliveries") or []
whatsapp = delivery.get("whatsapp") or {}
whatsapp_attempts = whatsapp.get("attempts") or []
whatsapp_claims = whatsapp.get("claim_history") or []
current_state = delivery.get("current_state") or "(none)"

print(f"task_id: {task.get('task_id', '')}")
print(f"task_status: {task.get('status', '')}")
print(f"delivery_state: {current_state}")
print("user_facing_ready: " + ("yes" if delivery.get("user_facing_ready") else "no"))
print("visible_artifact_required: " + ("yes" if delivery.get("visible_artifact_required") else "no"))
print("visible_artifact_ready: " + ("yes" if delivery.get("visible_artifact_ready") else "no"))
print(
    "minimum_user_facing_success_state: "
    + str(delivery.get("minimum_user_facing_success_state") or "visible")
)
print("whatsapp_delivery_required: " + ("yes" if whatsapp.get("required") else "no"))
print("whatsapp_delivery_state: " + str(whatsapp.get("current_state") or "(none)"))
print("whatsapp_delivery_confidence: " + str(whatsapp.get("delivery_confidence") or "(none)"))
print("whatsapp_allowed_user_facing_claim: " + str(whatsapp.get("allowed_user_facing_claim") or "(none)"))
message_ids = whatsapp.get("message_ids") or []
print("whatsapp_message_ids: " + (",".join(message_ids) if message_ids else "(none)"))
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
    print(
        "last_user_facing_claim_visible_artifact_required: "
        + ("yes" if last_claim.get("visible_artifact_required") else "no")
    )
    print(
        "last_user_facing_claim_visible_artifact_ready: "
        + ("yes" if last_claim.get("visible_artifact_ready") else "no")
    )

print("delivery_transition | timestamp | actor | channel | evidence")
for transition in transitions:
    print(
        f"{transition.get('state', '')} | {transition.get('timestamp', '')} | "
        f"{transition.get('actor', '')} | {transition.get('channel', '')} | {transition.get('evidence', '')}"
    )

print(f"visible_artifact_delivery_count: {len(visible_artifact_deliveries)}")
if visible_artifact_deliveries:
    print(
        "visible_artifact_delivery | target | verification_result | resolved_path | "
        "exists | readable | owner | path_normalized | verified_at"
    )
    for delivery_entry in visible_artifact_deliveries:
        verification = delivery_entry.get("verification") or {}
        print(
            f"{delivery_entry.get('source_artifact_path', '')} | {delivery_entry.get('delivery_target', '')} | "
            f"{delivery_entry.get('verification_result', '')} | {delivery_entry.get('resolved_path', '')} | "
            f"{verification.get('exists', '')} | {verification.get('readable', '')} | "
            f"{verification.get('owner', '')} | {verification.get('path_normalized', '')} | "
            f"{delivery_entry.get('verified_at', '')}"
        )

print(f"whatsapp_attempt_count: {len(whatsapp_attempts)}")
if whatsapp_attempts:
    print(
        "whatsapp_attempt | timestamp | state | confidence | provider | to | message_id | run_id | allowed_claim | raw_result_excerpt"
    )
    for attempt in whatsapp_attempts:
        print(
            f"{attempt.get('channel', '')} | {attempt.get('timestamp', '')} | {attempt.get('delivery_state', '')} | "
            f"{attempt.get('delivery_confidence', '')} | {attempt.get('provider', '')} | {attempt.get('to', '')} | "
            f"{attempt.get('message_id', '')} | {attempt.get('run_id', '')} | {attempt.get('allowed_user_facing_claim', '')} | "
            f"{attempt.get('raw_result_excerpt', '')}"
        )

if claims:
    print(
        "user_facing_claim | allowed | timestamp | actor | channel | current_state | required_state | "
        "visible_artifact_required | visible_artifact_ready | evidence"
    )
    for claim in claims:
        print(
            f"{claim.get('claim', '')} | "
            + ("yes" if claim.get("allowed") else "no")
            + f" | {claim.get('timestamp', '')} | {claim.get('actor', '')} | {claim.get('channel', '')} | "
            f"{claim.get('current_state', '')} | {claim.get('required_state', '')} | "
            f"{'yes' if claim.get('visible_artifact_required') else 'no'} | "
            f"{'yes' if claim.get('visible_artifact_ready') else 'no'} | {claim.get('evidence', '')}"
        )

print(f"whatsapp_claim_count: {len(whatsapp_claims)}")
if whatsapp_claims:
    print(
        "whatsapp_claim | allowed | timestamp | actor | requested_claim_level | requested_claim_text | "
        "current_state | allowed_claim_level | allowed_user_facing_claim | message_id | evidence"
    )
    for claim in whatsapp_claims:
        print(
            f"{claim.get('channel', '')} | "
            + ("yes" if claim.get("allowed") else "no")
            + f" | {claim.get('timestamp', '')} | {claim.get('actor', '')} | "
            f"{claim.get('requested_claim_level', '')} | {claim.get('requested_claim_text', '')} | "
            f"{claim.get('current_state', '')} | {claim.get('allowed_claim_level', '')} | "
            f"{claim.get('allowed_user_facing_claim', '')} | {claim.get('message_id', '')} | {claim.get('evidence', '')}"
        )
PY
