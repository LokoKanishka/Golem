#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
actor="${2:-}"
channel="${3:-}"
evidence="${4:-}"
claim="${5:-user-facing success}"

if [ -z "$task_id" ] || [ -z "$actor" ] || [ -z "$channel" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, actor, channel o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-user-facing-claim.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

set +e
claim_output="$(
  python3 - "$task_path" "$tmp_path" "$actor" "$channel" "$evidence" "$claim" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
tmp_path = pathlib.Path(sys.argv[2])
actor, channel, evidence, claim = sys.argv[3:7]
ordered_states = ["submitted", "accepted", "delivered", "visible", "verified_by_user"]

task = json.loads(task_path.read_text(encoding="utf-8"))
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
delivery.setdefault("visible_artifact_required", False)
delivery.setdefault("visible_artifact_ready", False)
delivery.setdefault("visible_artifact_deliveries", [])
delivery.setdefault("whatsapp", {})
whatsapp = delivery["whatsapp"]
whatsapp.setdefault("protocol_version", "1.0")
whatsapp.setdefault("required", False)
whatsapp.setdefault("current_state", "")
whatsapp.setdefault("delivery_confidence", "unknown")
whatsapp.setdefault("allowed_claim_level", "")
whatsapp.setdefault("allowed_user_facing_claim", "")
whatsapp.setdefault("user_facing_ready", False)
whatsapp.setdefault("tracked_message_id", "")
whatsapp.setdefault("message_ids", [])
whatsapp.setdefault("provider", "")
whatsapp.setdefault("to", "")
whatsapp.setdefault("run_id", "")
whatsapp.setdefault("attempts", [])
whatsapp.setdefault("claim_history", [])
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])
media = task.setdefault("media", {})
media.setdefault("protocol_version", "1.0")
media.setdefault("required", False)
media.setdefault("current_state", "none")
media.setdefault("ready", False)
media.setdefault("allowed_for_delivery", False)
media.setdefault("items", [])
media.setdefault("events", [])
media.setdefault("last_event_at", "")
media.setdefault("last_event_reason", "")
screenshot = task.setdefault("screenshot", {})
screenshot.setdefault("protocol_version", "1.0")
screenshot.setdefault("required", False)
screenshot.setdefault("current_state", "none")
screenshot.setdefault("ready_for_claim", False)
screenshot.setdefault("items", [])
screenshot.setdefault("events", [])
screenshot.setdefault("last_transition_at", "")
screenshot.setdefault("last_verified_at", "")
screenshot.setdefault("block_reason", "")
screenshot.setdefault("fail_reason", "")

current_state = delivery.get("current_state") or ""
required_state = delivery.get("minimum_user_facing_success_state") or "visible"
allowed = False
if current_state in ordered_states and required_state in ordered_states:
    allowed = ordered_states.index(current_state) >= ordered_states.index(required_state)

visible_artifact_required = bool(delivery.get("visible_artifact_required"))
visible_artifact_ready = bool(delivery.get("visible_artifact_ready"))
artifact_requirement_note = "not-required"
if visible_artifact_required:
    artifact_requirement_note = "verified" if visible_artifact_ready else "missing"
    allowed = allowed and visible_artifact_ready

whatsapp_required = bool(whatsapp.get("required"))
whatsapp_ready = bool(whatsapp.get("user_facing_ready"))
whatsapp_state = whatsapp.get("current_state") or ""
whatsapp_allowed_claim = whatsapp.get("allowed_user_facing_claim") or ""
whatsapp_requirement_note = "not-required"
if whatsapp_required:
    whatsapp_requirement_note = "verified" if whatsapp_ready else "missing"
    allowed = allowed and whatsapp_ready

media_required = bool(media.get("required"))
media_ready = bool(media.get("ready"))
media_state = media.get("current_state") or "none"
media_requirement_note = "not-required"
if media_required:
    media_requirement_note = "verified" if media_ready else "missing"
    allowed = allowed and media_ready

screenshot_required = bool(screenshot.get("required"))
screenshot_ready = bool(screenshot.get("ready_for_claim"))
screenshot_state = screenshot.get("current_state") or "none"
screenshot_requirement_note = "not-required"
if screenshot_required:
    screenshot_requirement_note = "verified" if screenshot_ready else "missing"
    allowed = allowed and screenshot_ready

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
claim_entry = {
    "claim": claim,
    "timestamp": now,
    "actor": actor,
    "channel": channel,
    "evidence": evidence,
    "required_state": required_state,
    "current_state": current_state,
    "visible_artifact_required": visible_artifact_required,
    "visible_artifact_ready": visible_artifact_ready,
    "artifact_requirement_note": artifact_requirement_note,
    "whatsapp_required": whatsapp_required,
    "whatsapp_delivery_state": whatsapp_state,
    "whatsapp_allowed_user_facing_claim": whatsapp_allowed_claim,
    "whatsapp_ready": whatsapp_ready,
    "whatsapp_requirement_note": whatsapp_requirement_note,
    "media_required": media_required,
    "media_state": media_state,
    "media_ready": media_ready,
    "media_requirement_note": media_requirement_note,
    "screenshot_required": screenshot_required,
    "screenshot_state": screenshot_state,
    "screenshot_ready": screenshot_ready,
    "screenshot_requirement_note": screenshot_requirement_note,
    "allowed": allowed,
}
delivery["claim_history"].append(claim_entry)
delivery["last_claim_at"] = now
delivery["last_claim_actor"] = actor
delivery["last_claim_channel"] = channel
task["updated_at"] = now

tmp_path.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

if allowed:
    print(f"TASK_USER_FACING_CLAIM_ALLOWED {task.get('task_id', '')} current_state={current_state}")
    raise SystemExit(0)

print(
    "TASK_USER_FACING_CLAIM_BLOCKED "
    f"{task.get('task_id', '')} current_state={current_state or '(none)'} required_state={required_state} "
    f"artifact_requirement={artifact_requirement_note} whatsapp_requirement={whatsapp_requirement_note} "
    f"media_requirement={media_requirement_note} screenshot_requirement={screenshot_requirement_note}"
)
raise SystemExit(2)
PY
)"
claim_exit="$?"
set -e

mv "$tmp_path" "$task_path"
trap - EXIT
printf '%s\n' "$claim_output"
exit "$claim_exit"
