#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_record_whatsapp_provider_delivery.sh <task_id> <actor> <provider> <to> <message_id> <provider_signal> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>] [--provider-status <status>] [--reason <reason>] [--normalized-evidence-json <json>]

provider_signal:
  ambiguous
  delivered
  verified_by_user
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
actor="${2:-}"
provider="${3:-}"
to="${4:-}"
message_id="${5:-}"
provider_signal="${6:-}"
raw_result_excerpt="${7:-}"
shift 7 || true

run_id=""
channel="whatsapp"
confidence=""
provider_status=""
reason=""
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
    --provider-status)
      shift
      provider_status="${1:-}"
      ;;
    --reason)
      shift
      reason="${1:-}"
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

if [ -z "$task_id" ] || [ -z "$actor" ] || [ -z "$provider" ] || [ -z "$to" ] || [ -z "$message_id" ] || [ -z "$provider_signal" ] || [ -z "$raw_result_excerpt" ]; then
  usage
  fatal "faltan task_id, actor, provider, to, message_id, provider_signal o raw_result_excerpt"
fi

state=""
evidence_kind=""
default_confidence=""
default_provider_status=""
default_reason=""

case "$provider_signal" in
  ambiguous)
    state="provider_delivery_unproved"
    evidence_kind="provider_delivery_unproved"
    default_confidence="low"
    default_provider_status="provider_delivery_unproved"
    default_reason="provider evidence is present but remains inconclusive for real delivery"
    ;;
  delivered)
    state="delivered"
    evidence_kind="provider_delivery_proof"
    default_confidence="high"
    default_provider_status="provider_delivery_proved"
    default_reason="provider evidence proves the message reached the destination channel"
    ;;
  verified_by_user)
    state="verified_by_user"
    evidence_kind="user_confirmation"
    default_confidence="confirmed"
    default_provider_status="verified_by_user"
    default_reason="the user explicitly confirmed the delivery outcome"
    ;;
  *)
    usage
    fatal "provider_signal invalido: $provider_signal"
    ;;
esac

cmd=(
  "$SCRIPT_DIR/task_record_whatsapp_delivery.sh"
  "$task_id"
  "$state"
  "$actor"
  "$provider"
  "$to"
  "$message_id"
  "$raw_result_excerpt"
  --run-id "$run_id"
  --channel "$channel"
  --confidence "${confidence:-$default_confidence}"
  --evidence-kind "$evidence_kind"
  --provider-status "${provider_status:-$default_provider_status}"
  --provider-reason "${reason:-$default_reason}"
)

if [ -n "$normalized_evidence_json" ]; then
  cmd+=(--normalized-evidence-json "$normalized_evidence_json")
fi

"${cmd[@]}"
