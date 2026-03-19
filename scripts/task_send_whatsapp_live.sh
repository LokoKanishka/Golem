#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_send_whatsapp_live.sh <task_id> <to> [--message <text>] [--media <path>] [--actor <actor>] [--evidence <text>] [--dry-run] [--json]

Fixtures de verify:
  GOLEM_WHATSAPP_SEND_FIXTURE_JSON='<json>'
  GOLEM_WHATSAPP_SEND_FIXTURE_PATH=/ruta/fixture.json
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_field() {
  local task_id="$1"
  local path_expr="$2"
  python3 - "$TASKS_DIR/${task_id}.json" "$path_expr" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
path_expr = sys.argv[2]
value = json.loads(task_path.read_text(encoding="utf-8"))

for part in path_expr.split("."):
    if not part:
        continue
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part, "")

if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=True))
else:
    print(value)
PY
}

sanitize_excerpt() {
  python3 - "$1" <<'PY'
import sys
text = sys.argv[1].replace("\n", " ").replace("\r", " ")
text = " ".join(text.split())
print(text[:240])
PY
}

resolve_media_path() {
  local media_raw="$1"
  python3 - "$REPO_ROOT" "$media_raw" <<'PY'
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
raw = sys.argv[2]
path = pathlib.Path(raw).expanduser()
if not path.is_absolute():
    path = (repo_root / raw).resolve(strict=False)
print(path.resolve(strict=False))
PY
}

task_id="${1:-}"
to="${2:-}"
shift 2 || true

message_text=""
media_path=""
actor="task-send-whatsapp-live"
evidence="canonical task-bound whatsapp live send wrapper invoked"
output_json="0"
dry_run="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --message)
      shift
      message_text="${1:-}"
      ;;
    --media)
      shift
      media_path="${1:-}"
      ;;
    --actor)
      shift
      actor="${1:-}"
      ;;
    --evidence)
      shift
      evidence="${1:-}"
      ;;
    --dry-run)
      dry_run="1"
      ;;
    --json)
      output_json="1"
      ;;
    *)
      usage
      fatal "argumento no soportado: $1"
      ;;
  esac
  shift || true
done

if [ -z "$task_id" ] || [ -z "$to" ]; then
  usage
  fatal "faltan task_id o to"
fi

if [ -z "$message_text" ] && [ -z "$media_path" ]; then
  usage
  fatal "hay que enviar al menos message o media"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

mkdir -p "$OUTBOX_DIR"

normalized_media_path=""
if [ -n "$media_path" ]; then
  normalized_media_path="$(resolve_media_path "$media_path")"
  if [ ! -f "$normalized_media_path" ]; then
    printf 'TASK_WHATSAPP_LIVE_SEND_BLOCKED %s reason=media_path_missing\n' "$task_id"
    exit 2
  fi
  media_gate_json="$(python3 - "$task_path" "$normalized_media_path" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
normalized_path = sys.argv[2]
media = task.get("media") or {}
items = media.get("items") or []
matching = [
    item for item in items
    if item.get("normalized_path") == normalized_path and item.get("current_state") == "verified"
]
payload = {
    "required": bool(media.get("required")),
    "ready": bool(media.get("ready")),
    "matching_verified": bool(matching),
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
  media_required="$(python3 - "$media_gate_json" <<'PY'
import json
import sys
print("yes" if json.loads(sys.argv[1]).get("required") else "no")
PY
)"
  media_matching_verified="$(python3 - "$media_gate_json" <<'PY'
import json
import sys
print("yes" if json.loads(sys.argv[1]).get("matching_verified") else "no")
PY
)"
  if [ "$media_matching_verified" != "yes" ]; then
    printf 'TASK_WHATSAPP_LIVE_SEND_BLOCKED %s reason=media_not_verified_for_send path=%s\n' "$task_id" "$normalized_media_path"
    exit 2
  fi
fi

current_whatsapp_state="$(task_field "$task_id" delivery.whatsapp.current_state)"
tracked_message_id="$(task_field "$task_id" delivery.whatsapp.tracked_message_id)"
current_whatsapp_state="${current_whatsapp_state:-}"
tracked_message_id="${tracked_message_id:-}"
allow_progressed_replay="0"
if [ -n "$current_whatsapp_state" ] && [ "$current_whatsapp_state" != "requested" ]; then
  if [ "$current_whatsapp_state" = "accepted_by_gateway" ] && { [ -n "${GOLEM_WHATSAPP_SEND_FIXTURE_JSON:-}" ] || [ -n "${GOLEM_WHATSAPP_SEND_FIXTURE_PATH:-}" ] || [ "$dry_run" = "1" ]; }; then
    allow_progressed_replay="1"
  else
    printf 'TASK_WHATSAPP_LIVE_SEND_FAIL %s reason=whatsapp_state_already_progressed state=%s\n' "$task_id" "$current_whatsapp_state" >&2
    exit 1
  fi
fi

if [ -z "$current_whatsapp_state" ]; then
  ./scripts/task_record_whatsapp_delivery.sh \
    "$task_id" \
    requested \
    "$actor" \
    openclaw-message-send \
    "$to" \
    - \
    "$(sanitize_excerpt "$evidence")" \
    --run-id "whatsapp-live-send-requested" \
    --evidence-kind send_request \
    --provider-status send_requested \
    --provider-reason "the wrapper registered the outbound intent before any gateway or provider proof" >/dev/null
fi

run_id="$(
  python3 - <<'PY'
import datetime
import uuid
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
print(f"run-{ts}-{uuid.uuid4().hex[:8]}")
PY
)"
report_path="$OUTBOX_DIR/${run_id}-whatsapp-live-send.json"
report_rel="${report_path#$REPO_ROOT/}"

command_display="openclaw message send --channel whatsapp --target '$to'"
if [ -n "$message_text" ]; then
  command_display="$command_display --message '$message_text'"
fi
if [ -n "$normalized_media_path" ]; then
  command_display="$command_display --media '$normalized_media_path'"
fi
command_display="$command_display --json"
if [ "$dry_run" = "1" ]; then
  command_display="$command_display --dry-run"
fi

surface_mode="openclaw-message-send"
surface_output=""
surface_exit="0"

if [ -n "${GOLEM_WHATSAPP_SEND_FIXTURE_JSON:-}" ]; then
  surface_mode="fixture-json"
  surface_output="${GOLEM_WHATSAPP_SEND_FIXTURE_JSON}"
elif [ -n "${GOLEM_WHATSAPP_SEND_FIXTURE_PATH:-}" ]; then
  surface_mode="fixture-path"
  if [ ! -f "${GOLEM_WHATSAPP_SEND_FIXTURE_PATH}" ]; then
    printf 'TASK_WHATSAPP_LIVE_SEND_FAIL %s reason=fixture_path_missing\n' "$task_id" >&2
    exit 1
  fi
  surface_output="$(cat "${GOLEM_WHATSAPP_SEND_FIXTURE_PATH}")"
else
  cmd=(openclaw message send --channel whatsapp --target "$to" --json)
  if [ -n "$message_text" ]; then
    cmd+=(--message "$message_text")
  fi
  if [ -n "$normalized_media_path" ]; then
    cmd+=(--media "$normalized_media_path")
  fi
  if [ "$dry_run" = "1" ]; then
    cmd+=(--dry-run)
  fi
  set +e
  surface_output="$("${cmd[@]}" 2>&1)"
  surface_exit="$?"
  set -e
fi

parsed_json="$(python3 - "$surface_output" <<'PY'
import json
import pathlib
import sys

text = sys.argv[1]
decoder = json.JSONDecoder()
for index, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, _ = decoder.raw_decode(text[index:])
        print(json.dumps(obj, ensure_ascii=True))
        raise SystemExit(0)
    except Exception:
        continue
print("")
PY
)"

parsed_summary="$(python3 - "$parsed_json" "$to" <<'PY'
import json
import sys

parsed_raw = sys.argv[1]
fallback_to = sys.argv[2]
payload = {}
if parsed_raw:
    payload = json.loads(parsed_raw)

def deep_get(container, path):
    value = container
    for key in path:
        if not isinstance(value, dict):
            return ""
        value = value.get(key, "")
    return value

message_id_candidates = [
    payload.get("messageId", ""),
    payload.get("message_id", ""),
    payload.get("providerMessageId", ""),
    payload.get("provider_message_id", ""),
    deep_get(payload, ["payload", "messageId"]),
    deep_get(payload, ["payload", "message_id"]),
    deep_get(payload, ["payload", "result", "messageId"]),
    deep_get(payload, ["payload", "result", "message_id"]),
    deep_get(payload, ["result", "messageId"]),
    deep_get(payload, ["data", "messageId"]),
]
message_id = ""
for candidate in message_id_candidates:
    if candidate:
        message_id = str(candidate)
        break

channel = str(payload.get("channel", "") or deep_get(payload, ["payload", "channel"]) or "whatsapp")
to_value = str(payload.get("to", "") or deep_get(payload, ["payload", "to"]) or fallback_to)
provider = str(payload.get("provider", "") or payload.get("handledBy", "") or deep_get(payload, ["payload", "via"]) or "openclaw-message-send")
dry_run = bool(payload.get("dryRun", False) or deep_get(payload, ["payload", "dryRun"]))
print(json.dumps({
    "message_id": message_id,
    "channel": channel,
    "to": to_value,
    "provider": provider,
    "dry_run": dry_run,
}, ensure_ascii=True))
PY
)"

parsed_message_id="$(python3 - "$parsed_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("message_id", ""))
PY
)"
parsed_channel="$(python3 - "$parsed_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("channel", "whatsapp"))
PY
)"
parsed_to="$(python3 - "$parsed_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("to", ""))
PY
)"
parsed_provider="$(python3 - "$parsed_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("provider", "openclaw-message-send"))
PY
)"
parsed_dry_run="$(python3 - "$parsed_summary" <<'PY'
import json
import sys
print("yes" if json.loads(sys.argv[1]).get("dry_run") else "no")
PY
)"

provider_proof_summary="$(python3 - "$parsed_json" <<'PY'
import json
import sys

parsed_raw = sys.argv[1]
payload = json.loads(parsed_raw) if parsed_raw else {}

status_candidates = []
bool_candidates = []
proof_candidates = []

def walk(value, path):
    if isinstance(value, dict):
        for key, child in value.items():
            key_lower = str(key).lower()
            child_path = path + [str(key)]
            if key_lower in {
                "status",
                "state",
                "deliverystatus",
                "delivery_status",
                "providerstatus",
                "provider_status",
                "receiptstatus",
                "receipt_status",
                "messagestatus",
                "message_status",
            } and isinstance(child, (str, int, float, bool)):
                status_candidates.append({"path": child_path, "value": child})
            if key_lower in {
                "delivered",
                "providerdelivered",
                "provider_delivered",
                "deliveryproved",
                "delivery_proved",
            } and isinstance(child, bool):
                bool_candidates.append({"path": child_path, "value": child})
            if key_lower in {"proofstrength", "proof_strength"} and isinstance(child, str):
                proof_candidates.append({"path": child_path, "value": child})
            walk(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk(child, path + [str(index)])

walk(payload, [])

delivered_statuses = {
    "delivered",
    "delivery_confirmed",
    "provider_delivered",
    "read",
    "read_by_recipient",
    "confirmed",
}
ambiguous_statuses = {
    "pending",
    "queued",
    "sent",
    "submitted",
    "accepted",
    "accepted_by_provider",
    "accepted_by_gateway",
    "processing",
    "enqueued",
}
strong_proof_values = {"strong", "confirmed"}

signal = "none"
provider_status = ""
reason = "no explicit provider delivery evidence was found in the live send response"

normalized = {
    "status_candidates": status_candidates,
    "boolean_candidates": bool_candidates,
    "proof_strength_candidates": proof_candidates,
}

truthy_bool = next((item for item in bool_candidates if item.get("value") is True), None)
falsy_bool = next((item for item in bool_candidates if item.get("value") is False), None)
matching_delivered = None
matching_ambiguous = None
for candidate in status_candidates:
    value = str(candidate.get("value", "")).strip().lower()
    if value in delivered_statuses and matching_delivered is None:
        matching_delivered = candidate
    if value in ambiguous_statuses and matching_ambiguous is None:
        matching_ambiguous = candidate

strong_proof = next(
    (
        item for item in proof_candidates
        if str(item.get("value", "")).strip().lower() in strong_proof_values
    ),
    None,
)

if truthy_bool or matching_delivered or strong_proof:
    signal = "delivered"
    if matching_delivered:
        provider_status = str(matching_delivered.get("value", ""))
    elif strong_proof:
        provider_status = str(strong_proof.get("value", ""))
    else:
        provider_status = "delivered"
    reason = "the live send response exposed explicit provider delivery proof"
elif falsy_bool or matching_ambiguous or status_candidates or proof_candidates:
    signal = "ambiguous"
    if matching_ambiguous:
        provider_status = str(matching_ambiguous.get("value", ""))
    elif falsy_bool:
        provider_status = "delivered=false"
    else:
        provider_status = "provider_delivery_unproved"
    reason = "the live send response exposed provider-side evidence, but it did not prove delivery"

print(json.dumps({
    "signal": signal,
    "provider_status": provider_status,
    "reason": reason,
    "normalized_evidence": normalized,
}, ensure_ascii=True))
PY
)"
provider_signal="$(python3 - "$provider_proof_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("signal", "none"))
PY
)"
provider_signal_status="$(python3 - "$provider_proof_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("provider_status", ""))
PY
)"
provider_signal_reason="$(python3 - "$provider_proof_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("reason", ""))
PY
)"
provider_signal_normalized_json="$(python3 - "$provider_proof_summary" <<'PY'
import json
import sys
print(json.dumps(json.loads(sys.argv[1]).get("normalized_evidence", {}), ensure_ascii=True))
PY
)"

raw_excerpt="$(sanitize_excerpt "$surface_output")"
wrapper_state="requested"
wrapper_status="DRY_RUN"
wrapper_exit_code="0"
final_note="whatsapp live send wrapper invoked safely in dry-run mode"
drift_expected=""
drift_actual=""

if [ -n "$tracked_message_id" ] && [ -n "$parsed_message_id" ] && [ "$parsed_message_id" != "$tracked_message_id" ]; then
  drift_expected="$tracked_message_id"
  drift_actual="$parsed_message_id"
fi

if [ "$surface_exit" -ne 0 ]; then
  wrapper_state="requested"
  wrapper_status="BLOCKED"
  wrapper_exit_code="2"
  final_note="whatsapp live send surface did not complete cleanly"
elif [ -n "$drift_expected" ]; then
  wrapper_state="accepted_by_gateway"
  wrapper_status="FAIL"
  wrapper_exit_code="1"
  final_note="whatsapp live send wrapper detected message_id drift against the tracked task evidence"
elif [ "$allow_progressed_replay" = "1" ]; then
  wrapper_state="accepted_by_gateway"
  wrapper_status="BLOCKED"
  wrapper_exit_code="2"
  final_note="whatsapp live send wrapper refused to progress a task that already has gateway acceptance evidence"
elif [ "$parsed_dry_run" = "yes" ] || [ "$dry_run" = "1" ]; then
  wrapper_state="requested"
  wrapper_status="DRY_RUN"
  wrapper_exit_code="0"
  final_note="whatsapp live send wrapper completed a safe dry-run without gateway acceptance evidence"
elif [ -n "$parsed_message_id" ]; then
  ./scripts/task_record_whatsapp_delivery.sh \
    "$task_id" \
    accepted_by_gateway \
    "$actor" \
    "$parsed_provider" \
    "$parsed_to" \
    "$parsed_message_id" \
    "$raw_excerpt" \
    --run-id "$run_id" \
    --channel "$parsed_channel" \
    --evidence-kind gateway_acceptance \
    --provider-status gateway_accepted \
    --provider-reason "the gateway accepted the message but the provider has not yet proved delivery" >/dev/null
  if [ "$provider_signal" = "delivered" ]; then
    ./scripts/task_record_whatsapp_provider_delivery.sh \
      "$task_id" \
      "$actor" \
      "$parsed_provider" \
      "$parsed_to" \
      "$parsed_message_id" \
      delivered \
      "$raw_excerpt" \
      --run-id "$run_id" \
      --channel "$parsed_channel" \
      --provider-status "${provider_signal_status:-provider_delivered}" \
      --reason "$provider_signal_reason" \
      --normalized-evidence-json "$provider_signal_normalized_json" >/dev/null
    wrapper_state="delivered"
    wrapper_status="DELIVERED"
    wrapper_exit_code="0"
    final_note="whatsapp live send wrapper captured strong provider delivery proof and persisted delivered state"
  elif [ "$provider_signal" = "ambiguous" ]; then
    ./scripts/task_record_whatsapp_provider_delivery.sh \
      "$task_id" \
      "$actor" \
      "$parsed_provider" \
      "$parsed_to" \
      "$parsed_message_id" \
      ambiguous \
      "$raw_excerpt" \
      --run-id "$run_id" \
      --channel "$parsed_channel" \
      --provider-status "${provider_signal_status:-provider_delivery_unproved}" \
      --reason "$provider_signal_reason" \
      --normalized-evidence-json "$provider_signal_normalized_json" >/dev/null
    wrapper_state="provider_delivery_unproved"
    wrapper_status="PROVIDER_DELIVERY_UNPROVED"
    wrapper_exit_code="0"
    final_note="whatsapp live send wrapper captured provider-side evidence but it still did not prove delivery"
  else
    wrapper_state="accepted_by_gateway"
    wrapper_status="ACCEPTED_BY_GATEWAY"
    wrapper_exit_code="0"
    final_note="whatsapp live send wrapper captured gateway acceptance evidence and persisted message_id"
  fi
else
  wrapper_state="requested"
  wrapper_status="BLOCKED"
  wrapper_exit_code="2"
  final_note="whatsapp live send surface responded but did not expose auditable gateway acceptance evidence"
fi

python3 - "$report_path" "$task_id" "$to" "$message_text" "$normalized_media_path" "$command_display" "$surface_mode" "$surface_exit" "$parsed_json" "$parsed_summary" "$run_id" "$wrapper_state" "$wrapper_status" "$final_note" "$raw_excerpt" "$drift_expected" "$drift_actual" "$provider_proof_summary" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
task_id, to_value, message_text, media_path, command_display, surface_mode, surface_exit, parsed_raw, summary_raw, run_id, wrapper_state, wrapper_status, final_note, raw_excerpt, drift_expected, drift_actual, provider_summary_raw = sys.argv[2:19]
parsed = json.loads(parsed_raw) if parsed_raw else {}
summary = json.loads(summary_raw)
provider_summary = json.loads(provider_summary_raw)

report_payload = {
    "task_id": task_id,
    "to": to_value,
    "message": message_text,
    "media_path": media_path,
    "command": command_display,
    "surface_mode": surface_mode,
    "surface_exit_code": int(surface_exit),
    "parsed_result": parsed,
    "parsed_summary": summary,
    "run_id": run_id,
    "wrapper_state": wrapper_state,
    "wrapper_status": wrapper_status,
    "provider_proof_summary": provider_summary,
    "note": final_note,
    "raw_result_excerpt": raw_excerpt,
    "message_id_drift": {
        "expected": drift_expected,
        "actual": drift_actual,
        "detected": bool(drift_expected and drift_actual),
    },
}

report_path.write_text(json.dumps(report_payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

TASK_ARTIFACT_EXTRA_JSON="$(python3 - "$run_id" "$wrapper_status" "$wrapper_state" <<'PY'
import json
import sys
print(json.dumps({
    "run_id": sys.argv[1],
    "wrapper_status": sys.argv[2],
    "wrapper_state": sys.argv[3],
}, ensure_ascii=True))
PY
)" ./scripts/task_add_artifact.sh "$task_id" whatsapp-live-send-report "$report_rel" >/dev/null

TASK_OUTPUT_EXTRA_JSON="$(python3 - "$parsed_json" "$parsed_summary" "$command_display" "$surface_mode" "$surface_exit" "$to" "$message_text" "$normalized_media_path" "$run_id" "$wrapper_state" "$raw_excerpt" "$provider_proof_summary" <<'PY'
import json
import sys

parsed = json.loads(sys.argv[1]) if sys.argv[1] else {}
summary = json.loads(sys.argv[2])
payload = {
    "command": sys.argv[3],
    "surface_mode": sys.argv[4],
    "surface_exit_code": int(sys.argv[5]),
    "to": sys.argv[6],
    "message": sys.argv[7],
    "media_path": sys.argv[8],
    "run_id": sys.argv[9],
    "wrapper_state": sys.argv[10],
    "raw_result_excerpt": sys.argv[11],
    "provider_proof_summary": json.loads(sys.argv[12]),
    "report_path": "",
    "parsed_result": parsed,
    "parsed_summary": summary,
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
TASK_OUTPUT_EXTRA_JSON="$(python3 - "$TASK_OUTPUT_EXTRA_JSON" "$report_rel" "$wrapper_status" "$drift_expected" "$drift_actual" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
payload["report_path"] = sys.argv[2]
payload["wrapper_status"] = sys.argv[3]
payload["message_id_drift_expected"] = sys.argv[4]
payload["message_id_drift_actual"] = sys.argv[5]
print(json.dumps(payload, ensure_ascii=True))
PY
)" ./scripts/task_add_output.sh "$task_id" whatsapp-live-send "$wrapper_exit_code" "$final_note" >/dev/null

result_json="$(python3 - "$task_path" "$task_id" "$parsed_to" "$parsed_message_id" "$parsed_provider" "$run_id" "$wrapper_state" "$wrapper_status" "$raw_excerpt" "$final_note" "$command_display" "$surface_mode" "$surface_exit" "$normalized_media_path" "$parsed_dry_run" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
task_id, to_value, message_id, provider, run_id, wrapper_state, wrapper_status, raw_excerpt, final_note, command_display, surface_mode, surface_exit, media_path, dry_run = sys.argv[2:16]
print(json.dumps({
    "task_id": task_id,
    "to": to_value,
    "message_id": message_id,
    "provider": provider,
    "run_id": run_id,
    "wrapper_state": wrapper_state,
    "wrapper_status": wrapper_status,
    "delivery_whatsapp_state": (((task.get("delivery") or {}).get("whatsapp") or {}).get("current_state") or ""),
    "allowed_user_facing_claim": (((task.get("delivery") or {}).get("whatsapp") or {}).get("allowed_user_facing_claim") or ""),
    "provider_delivery_status": (((task.get("delivery") or {}).get("whatsapp") or {}).get("provider_delivery_status") or ""),
    "provider_delivery_reason": (((task.get("delivery") or {}).get("whatsapp") or {}).get("provider_delivery_reason") or ""),
    "raw_result_excerpt": raw_excerpt,
    "note": final_note,
    "command": command_display,
    "surface_mode": surface_mode,
    "surface_exit_code": int(surface_exit),
    "media_path": media_path,
    "dry_run": dry_run == "yes",
    "report_path": "",
}, ensure_ascii=True))
PY
)"
result_json="$(python3 - "$result_json" "$report_path" "$drift_expected" "$drift_actual" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
payload["report_path"] = sys.argv[2]
payload["message_id_drift_expected"] = sys.argv[3]
payload["message_id_drift_actual"] = sys.argv[4]
print(json.dumps(payload, ensure_ascii=True))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$result_json"
else
  printf 'TASK_WHATSAPP_LIVE_SEND_%s %s state=%s message_id=%s run_id=%s\n' "$wrapper_status" "$task_id" "$wrapper_state" "${parsed_message_id:--}" "$run_id"
fi

case "$wrapper_exit_code" in
  0) exit 0 ;;
  2) exit 2 ;;
  *) exit 1 ;;
esac
