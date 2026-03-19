#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_record_whatsapp_delivery.sh <task_id> <state> <actor> <provider> <to> <message_id|-> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>] [--evidence-kind <kind>] [--provider-status <status>] [--provider-reason <reason>] [--normalized-evidence-json <json>]
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
evidence_kind=""
provider_status=""
provider_reason=""
normalized_evidence_json=""
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
    --evidence-kind)
      shift
      evidence_kind="${1:-}"
      ;;
    --provider-status)
      shift
      provider_status="${1:-}"
      ;;
    --provider-reason)
      shift
      provider_reason="${1:-}"
      ;;
    --normalized-evidence-json)
      shift
      normalized_evidence_json="${1:-}"
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

python3 - "$task_path" "$state" "$actor" "$provider" "$to" "$message_id" "$raw_result_excerpt" "$run_id" "$channel" "$confidence" "$evidence_kind" "$provider_status" "$provider_reason" "$normalized_evidence_json" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
state, actor, provider, to, message_id, raw_result_excerpt, run_id, channel, confidence, evidence_kind, provider_status, provider_reason, normalized_evidence_json = sys.argv[2:15]

state_aliases = {
    "accepted_by_provider": "provider_delivery_unproved",
}

canonical_state = state_aliases.get(state, state)

ordered_states = [
    "requested",
    "accepted_by_gateway",
    "provider_delivery_unproved",
    "delivered",
    "verified_by_user",
]
allowed_claims = {
    "requested": "solicitado",
    "accepted_by_gateway": "aceptado por gateway",
    "provider_delivery_unproved": "sin prueba concluyente del proveedor",
    "delivered": "entregado",
    "verified_by_user": "confirmado por usuario",
}
default_confidence = {
    "requested": "low",
    "accepted_by_gateway": "medium",
    "provider_delivery_unproved": "low",
    "delivered": "high",
    "verified_by_user": "confirmed",
}
allowed_next_states = {
    "": {"requested"},
    "requested": {"accepted_by_gateway"},
    "accepted_by_gateway": {"provider_delivery_unproved", "delivered"},
    "provider_delivery_unproved": {"delivered"},
    "delivered": {"verified_by_user"},
    "verified_by_user": set(),
}

if canonical_state not in ordered_states:
    raise SystemExit(
        "ERROR: state invalido. Usar uno de: requested, accepted_by_gateway, provider_delivery_unproved, delivered, verified_by_user"
    )

normalized_message_id = "" if message_id in {"", "-"} else message_id
if canonical_state != "requested" and not normalized_message_id:
    raise SystemExit("ERROR: message_id es obligatorio desde accepted_by_gateway en adelante")

normalized_evidence = {}
if normalized_evidence_json:
    try:
        normalized_evidence = json.loads(normalized_evidence_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: normalized_evidence_json invalido: {exc}") from exc
    if not isinstance(normalized_evidence, dict):
        raise SystemExit("ERROR: normalized_evidence_json debe ser un objeto JSON")

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
whatsapp.setdefault("provider_delivery_status", "")
whatsapp.setdefault("provider_delivery_reason", "")
whatsapp.setdefault("provider_delivery_proof_at", "")
whatsapp.setdefault("last_provider_evidence_at", "")
whatsapp.setdefault("attempts", [])
whatsapp.setdefault("claim_history", [])

current_state = state_aliases.get(whatsapp.get("current_state") or "", whatsapp.get("current_state") or "")
if canonical_state == current_state:
    raise SystemExit(f"ERROR: la entrega de WhatsApp ya esta en state {canonical_state}")
if canonical_state not in allowed_next_states.get(current_state, set()):
    expected = ", ".join(sorted(allowed_next_states.get(current_state, set()))) or "ninguna mas"
    raise SystemExit(
        f"ERROR: transicion WhatsApp invalida: {current_state or '(none)'} -> {canonical_state}; se esperaba {expected}"
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

resolved_confidence = confidence or default_confidence[canonical_state]
allowed_claim_level = canonical_state
allowed_user_facing_claim = allowed_claims[canonical_state]
user_facing_ready = ordered_states.index(canonical_state) >= ordered_states.index("delivered")
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

provider_status_defaults = {
    "requested": "send_requested",
    "accepted_by_gateway": "gateway_accepted",
    "provider_delivery_unproved": "provider_delivery_unproved",
    "delivered": "provider_delivery_proved",
    "verified_by_user": "verified_by_user",
}
provider_reason_defaults = {
    "requested": "the task only has local send intent and no provider delivery evidence yet",
    "accepted_by_gateway": "the gateway accepted the outbound request but the provider still has not proved delivery",
    "provider_delivery_unproved": "provider evidence exists but does not prove that the message was delivered",
    "delivered": "provider evidence proves that the message was delivered",
    "verified_by_user": "the user explicitly confirmed the delivery outcome",
}
provider_status_value = provider_status or provider_status_defaults[canonical_state]
provider_reason_value = provider_reason or provider_reason_defaults[canonical_state]
evidence_kind_value = evidence_kind or {
    "requested": "send_request",
    "accepted_by_gateway": "gateway_acceptance",
    "provider_delivery_unproved": "provider_delivery_unproved",
    "delivered": "provider_delivery_proof",
    "verified_by_user": "user_confirmation",
}[canonical_state]

attempt = {
    "channel": channel,
    "provider": provider,
    "to": to,
    "message_id": normalized_message_id,
    "run_id": run_id,
    "timestamp": now,
    "delivery_state": canonical_state,
    "delivery_state_canonical": canonical_state,
    "delivery_confidence": resolved_confidence,
    "allowed_claim_level": allowed_claim_level,
    "allowed_user_facing_claim": allowed_user_facing_claim,
    "raw_result_excerpt": raw_result_excerpt,
    "provider_evidence_kind": evidence_kind_value,
    "provider_status": provider_status_value,
    "provider_reason": provider_reason_value,
    "provider_evidence_normalized": normalized_evidence,
    "delivery_proof_present": canonical_state in {"delivered", "verified_by_user"},
    "actor": actor,
}

whatsapp["required"] = True
whatsapp["current_state"] = canonical_state
whatsapp["delivery_confidence"] = resolved_confidence
whatsapp["allowed_claim_level"] = allowed_claim_level
whatsapp["allowed_user_facing_claim"] = allowed_user_facing_claim
whatsapp["user_facing_ready"] = user_facing_ready
whatsapp["tracked_message_id"] = tracked_message_id
whatsapp["provider"] = provider
whatsapp["to"] = to
whatsapp["run_id"] = run_id
whatsapp["provider_delivery_status"] = provider_status_value
whatsapp["provider_delivery_reason"] = provider_reason_value
whatsapp["last_attempt_at"] = now
whatsapp["last_actor"] = actor
whatsapp["last_provider_evidence_at"] = now
whatsapp["attempts"].append(attempt)
if normalized_message_id and normalized_message_id not in (whatsapp.get("message_ids") or []):
    whatsapp.setdefault("message_ids", []).append(normalized_message_id)
if canonical_state in {"delivered", "verified_by_user"}:
    whatsapp["provider_delivery_proof_at"] = now

task.setdefault("notes", []).append(
    f"whatsapp delivery {canonical_state} recorded for {to} with allowed claim '{allowed_user_facing_claim}'"
)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_WHATSAPP_DELIVERY_RECORDED %s %s message_id=%s\n' "$task_id" "$state" "${message_id:--}"
