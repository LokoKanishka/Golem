#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_record_whatsapp_delivery.sh <task_id> <state> <actor> <provider> <to> <message_id|-> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
state="${2:-}"
actor="${3:-}"
provider="${4:-}"
to="${5:-}"
message_id="${6:-}"
raw_result_excerpt="${7:-}"
shift 7 || true

run_id=""
channel="whatsapp"
confidence=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-id)
      shift
      run_id="${1:-}"
      ;;
    --channel)
      shift
      channel="${1:-}"
      ;;
    --confidence)
      shift
      confidence="${1:-}"
      ;;
    *)
      usage
      fatal "argumento no soportado: $1"
      ;;
  esac
  shift || true
done

if [ -z "$task_id" ] || [ -z "$state" ] || [ -z "$actor" ] || [ -z "$provider" ] || [ -z "$to" ] || [ -z "$raw_result_excerpt" ]; then
  usage
  fatal "faltan task_id, state, actor, provider, to, message_id o raw_result_excerpt"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-whatsapp-delivery.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$state" "$actor" "$provider" "$to" "$message_id" "$raw_result_excerpt" "$run_id" "$channel" "$confidence" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
state, actor, provider, to, message_id, raw_result_excerpt, run_id, channel, confidence = sys.argv[2:11]

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
default_confidence = {
    "requested": "low",
    "accepted_by_gateway": "medium",
    "accepted_by_provider": "medium",
    "delivered": "high",
    "verified_by_user": "confirmed",
}
allowed_next_states = {
    "": {"requested"},
    "requested": {"accepted_by_gateway"},
    "accepted_by_gateway": {"accepted_by_provider", "delivered"},
    "accepted_by_provider": {"delivered"},
    "delivered": {"verified_by_user"},
    "verified_by_user": set(),
}

if state not in ordered_states:
    raise SystemExit(
        "ERROR: state invalido. Usar uno de: requested, accepted_by_gateway, accepted_by_provider, delivered, verified_by_user"
    )

normalized_message_id = "" if message_id in {"", "-"} else message_id
if state != "requested" and not normalized_message_id:
    raise SystemExit("ERROR: message_id es obligatorio desde accepted_by_gateway en adelante")

task = json.loads(task_path.read_text(encoding="utf-8"))
delivery = task.setdefault("delivery", {})
delivery.setdefault("protocol_version", "1.0")
delivery.setdefault("minimum_user_facing_success_state", "visible")
delivery.setdefault("current_state", "")
delivery.setdefault("user_facing_ready", False)
delivery.setdefault("visible_artifact_required", False)
delivery.setdefault("visible_artifact_ready", False)
delivery.setdefault("visible_artifact_deliveries", [])
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])
whatsapp = delivery.setdefault("whatsapp", {})
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
if state == current_state:
    raise SystemExit(f"ERROR: la entrega de WhatsApp ya esta en state {state}")
if state not in allowed_next_states.get(current_state, set()):
    expected = ", ".join(sorted(allowed_next_states.get(current_state, set()))) or "ninguna mas"
    raise SystemExit(
        f"ERROR: transicion WhatsApp invalida: {current_state or '(none)'} -> {state}; se esperaba {expected}"
    )

tracked_message_id = whatsapp.get("tracked_message_id") or ""
if tracked_message_id and normalized_message_id and normalized_message_id != tracked_message_id:
    raise SystemExit(
        f"ERROR: drift de message_id: se esperaba {tracked_message_id} y llego {normalized_message_id}"
    )
if not tracked_message_id and normalized_message_id:
    tracked_message_id = normalized_message_id

if whatsapp.get("to") and whatsapp.get("to") != to:
    raise SystemExit(f"ERROR: drift de destinatario: se esperaba {whatsapp.get('to')} y llego {to}")

resolved_confidence = confidence or default_confidence[state]
allowed_claim_level = state
allowed_user_facing_claim = allowed_claims[state]
user_facing_ready = ordered_states.index(state) >= ordered_states.index("delivered")
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

attempt = {
    "channel": channel,
    "provider": provider,
    "to": to,
    "message_id": normalized_message_id,
    "run_id": run_id,
    "timestamp": now,
    "delivery_state": state,
    "delivery_confidence": resolved_confidence,
    "allowed_claim_level": allowed_claim_level,
    "allowed_user_facing_claim": allowed_user_facing_claim,
    "raw_result_excerpt": raw_result_excerpt,
    "actor": actor,
}

whatsapp["required"] = True
whatsapp["current_state"] = state
whatsapp["delivery_confidence"] = resolved_confidence
whatsapp["allowed_claim_level"] = allowed_claim_level
whatsapp["allowed_user_facing_claim"] = allowed_user_facing_claim
whatsapp["user_facing_ready"] = user_facing_ready
whatsapp["tracked_message_id"] = tracked_message_id
whatsapp["provider"] = provider
whatsapp["to"] = to
whatsapp["run_id"] = run_id
whatsapp["last_attempt_at"] = now
whatsapp["last_actor"] = actor
whatsapp["attempts"].append(attempt)
if normalized_message_id and normalized_message_id not in (whatsapp.get("message_ids") or []):
    whatsapp.setdefault("message_ids", []).append(normalized_message_id)

task.setdefault("notes", []).append(
    f"whatsapp delivery {state} recorded for {to} with allowed claim '{allowed_user_facing_claim}'"
)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_WHATSAPP_DELIVERY_RECORDED %s %s message_id=%s\n' "$task_id" "$state" "${message_id:--}"
