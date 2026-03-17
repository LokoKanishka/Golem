#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_claim_whatsapp_delivery.sh <task_id> <actor> <requested_claim_level> <evidence> [claim_text]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
actor="${2:-}"
requested_claim_level="${3:-}"
evidence="${4:-}"
claim_text="${5:-}"

if [ -z "$task_id" ] || [ -z "$actor" ] || [ -z "$requested_claim_level" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, actor, requested_claim_level o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-whatsapp-claim.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

set +e
claim_output="$(
  python3 - "$task_path" "$tmp_path" "$actor" "$requested_claim_level" "$evidence" "$claim_text" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
tmp_path = pathlib.Path(sys.argv[2])
actor, requested_claim_level, evidence, claim_text = sys.argv[3:7]

ordered_states = [
    "requested",
    "accepted_by_gateway",
    "accepted_by_provider",
    "delivered",
    "verified_by_user",
]
allowed_claims = {
    "requested": "solicitado",
    "accepted_by_gateway": "aceptado por gateway",
    "accepted_by_provider": "aceptado por proveedor",
    "delivered": "entregado",
    "verified_by_user": "confirmado por usuario",
}

if requested_claim_level not in ordered_states:
    raise SystemExit(
        "ERROR: requested_claim_level invalido. Usar uno de: requested, accepted_by_gateway, accepted_by_provider, delivered, verified_by_user"
    )

canonical_claim_text = allowed_claims[requested_claim_level]
if claim_text and claim_text != canonical_claim_text:
    raise SystemExit(
        f"ERROR: claim_text invalido para {requested_claim_level}; usar exactamente '{canonical_claim_text}' o dejarlo vacio"
    )

task = json.loads(task_path.read_text(encoding="utf-8"))
delivery = task.setdefault("delivery", {})
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

current_state = whatsapp.get("current_state") or ""
allowed_claim_level = whatsapp.get("allowed_claim_level") or ""
allowed_user_facing_claim = whatsapp.get("allowed_user_facing_claim") or ""
allowed = False
if current_state in ordered_states and requested_claim_level in ordered_states:
    allowed = ordered_states.index(requested_claim_level) <= ordered_states.index(current_state)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
claim_entry = {
    "channel": "whatsapp",
    "timestamp": now,
    "actor": actor,
    "requested_claim_level": requested_claim_level,
    "requested_claim_text": canonical_claim_text,
    "current_state": current_state,
    "allowed_claim_level": allowed_claim_level,
    "allowed_user_facing_claim": allowed_user_facing_claim,
    "delivery_confidence": whatsapp.get("delivery_confidence") or "",
    "message_id": whatsapp.get("tracked_message_id") or "",
    "evidence": evidence,
    "allowed": allowed,
}
whatsapp["claim_history"].append(claim_entry)
whatsapp["last_claim_at"] = now
whatsapp["last_claim_actor"] = actor
task["updated_at"] = now

tmp_path.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

if allowed:
    print(
        "TASK_WHATSAPP_CLAIM_ALLOWED "
        f"{task.get('task_id', '')} current_state={current_state} requested_claim_level={requested_claim_level}"
    )
    raise SystemExit(0)

print(
    "TASK_WHATSAPP_CLAIM_BLOCKED "
    f"{task.get('task_id', '')} current_state={current_state or '(none)'} "
    f"requested_claim_level={requested_claim_level} allowed_claim_level={allowed_claim_level or '(none)'}"
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
