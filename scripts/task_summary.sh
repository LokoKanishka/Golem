#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_summary.sh <task_id>
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

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

notes = task.get("notes", [])
last_note = notes[-1] if notes else "(none)"
parent_task_id = task.get("parent_task_id") or "(none)"
depends_on = task.get("depends_on") or []
chain_type = task.get("chain_type") or ""
chain_status = task.get("chain_status") or ""
chain_summary = task.get("chain_summary") or {}
chain_plan = task.get("chain_plan") or {}
worker_run = task.get("worker_run") or {}
delivery = task.get("delivery") or {}
delivery_transitions = delivery.get("transitions") or []
delivery_claim_history = delivery.get("claim_history") or []
delivery_state = delivery.get("current_state") or "(none)"
delivery_ready = "yes" if delivery.get("user_facing_ready") else "no"
visible_artifact_required = "yes" if delivery.get("visible_artifact_required") else "no"
visible_artifact_ready = "yes" if delivery.get("visible_artifact_ready") else "no"
visible_artifact_deliveries = delivery.get("visible_artifact_deliveries") or []
last_visible_artifact_delivery = visible_artifact_deliveries[-1] if visible_artifact_deliveries else {}
whatsapp = delivery.get("whatsapp") or {}
whatsapp_required = "yes" if whatsapp.get("required") else "no"
whatsapp_state = whatsapp.get("current_state") or "(none)"
whatsapp_confidence = whatsapp.get("delivery_confidence") or "(none)"
whatsapp_allowed_claim = whatsapp.get("allowed_user_facing_claim") or "(none)"
whatsapp_message_ids = whatsapp.get("message_ids") or []
delivery_last_transition = delivery_transitions[-1] if delivery_transitions else {}
delivery_last_claim = delivery_claim_history[-1] if delivery_claim_history else {}
step_name = task.get("step_name") or ""
step_order = task.get("step_order")
critical = task.get("critical")
execution_mode = task.get("execution_mode") or ""
media = task.get("media") or {}
media_state = media.get("current_state") or "none"
media_required = "yes" if media.get("required") else "no"
media_ready = "yes" if media.get("ready") else "no"
media_items = media.get("items") or []
last_media_item = media_items[-1] if media_items else {}

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"type: {task.get('type', '?')}")
print(f"status: {task.get('status', '?')}")
print(f"title: {task.get('title', '')}")
print(f"parent_task_id: {parent_task_id}")
print(f"depends_on: {len(depends_on)}")
if step_name:
    print(f"step_name: {step_name}")
if step_order is not None:
    print(f"step_order: {step_order}")
if critical is not None:
    print(f"critical: {'yes' if critical else 'no'}")
if execution_mode:
    print(f"execution_mode: {execution_mode}")
if chain_type:
    print(f"chain_type: {chain_type}")
if chain_status:
    print(f"chain_status: {chain_status}")
if task.get("validated_plan_version"):
    print(f"validated_plan_version: {task.get('validated_plan_version')}")
if task.get("effective_plan_path"):
    print(f"effective_plan_path: {task.get('effective_plan_path')}")
if task.get("preflight_artifact_path"):
    print(f"preflight_artifact_path: {task.get('preflight_artifact_path')}")
if chain_summary:
    print(f"child_count: {chain_summary.get('child_count', 0)}")
    if "step_count" in chain_summary:
        print(f"step_count: {chain_summary.get('step_count', 0)}")
    if "steps_completed" in chain_summary:
        print(f"steps_completed: {chain_summary.get('steps_completed', 0)}")
    if "steps_failed" in chain_summary:
        print(f"steps_failed: {chain_summary.get('steps_failed', 0)}")
    if chain_summary.get("final_artifact_path"):
        print(f"final_artifact_path: {chain_summary.get('final_artifact_path')}")
elif chain_plan:
    print(f"planned_steps: {len(chain_plan.get('steps') or [])}")
if worker_run:
    print(f"worker_state: {worker_run.get('state', '(none)')}")
    print(f"worker_result_status: {worker_run.get('result_status', '(none)')}")
    extracted_summary = worker_run.get("extracted_summary", "")
    if extracted_summary:
        print(f"worker_extracted_summary: {extracted_summary}")
print(f"delivery_state: {delivery_state}")
print(f"user_facing_ready: {delivery_ready}")
print(f"visible_artifact_required: {visible_artifact_required}")
print(f"visible_artifact_ready: {visible_artifact_ready}")
print(f"visible_artifact_deliveries: {len(visible_artifact_deliveries)}")
if last_visible_artifact_delivery:
    print(f"last_visible_artifact_target: {last_visible_artifact_delivery.get('delivery_target', '(none)')}")
    print(f"last_visible_artifact_result: {last_visible_artifact_delivery.get('verification_result', '(none)')}")
    print(f"last_visible_artifact_path: {last_visible_artifact_delivery.get('resolved_path', '(none)')}")
print(f"whatsapp_delivery_required: {whatsapp_required}")
print(f"whatsapp_delivery_state: {whatsapp_state}")
print(f"whatsapp_delivery_confidence: {whatsapp_confidence}")
print(f"whatsapp_message_ids: {len(whatsapp_message_ids)}")
if whatsapp_message_ids:
    print(f"whatsapp_message_id_list: {','.join(whatsapp_message_ids)}")
print(f"whatsapp_allowed_user_facing_claim: {whatsapp_allowed_claim}")
print(f"media_required: {media_required}")
print(f"media_state: {media_state}")
print(f"media_ready: {media_ready}")
print(f"media_items: {len(media_items)}")
if last_media_item:
    print(f"last_media_source_kind: {last_media_item.get('source_kind', '(none)')}")
    print(f"last_media_path: {last_media_item.get('normalized_path', '(none)')}")
    print(f"last_media_sha256: {last_media_item.get('sha256', '(none)')}")
print(f"delivery_transitions: {len(delivery_transitions)}")
if delivery_last_transition:
    print(f"last_delivery_transition: {delivery_last_transition.get('state', '(none)')}")
    print(f"last_delivery_timestamp: {delivery_last_transition.get('timestamp', '(none)')}")
    print(f"last_delivery_actor: {delivery_last_transition.get('actor', '(none)')}")
    print(f"last_delivery_channel: {delivery_last_transition.get('channel', '(none)')}")
print(f"user_facing_claims: {len(delivery_claim_history)}")
if delivery_last_claim:
    print("last_user_facing_claim_allowed: " + ("yes" if delivery_last_claim.get("allowed") else "no"))
    print(f"last_user_facing_claim_state: {delivery_last_claim.get('current_state', '(none)')}")
    if "whatsapp_delivery_state" in delivery_last_claim:
        print(f"last_user_facing_claim_whatsapp_state: {delivery_last_claim.get('whatsapp_delivery_state', '(none)')}")
    if "media_state" in delivery_last_claim:
        print(f"last_user_facing_claim_media_state: {delivery_last_claim.get('media_state', '(none)')}")
print(f"outputs: {len(task.get('outputs', []))}")
print(f"artifacts: {len(task.get('artifacts', []))}")
print(f"last_note: {last_note}")
PY
