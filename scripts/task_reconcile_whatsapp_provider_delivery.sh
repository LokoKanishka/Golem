#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_reconcile_whatsapp_provider_delivery.sh <task_id> [--actor <actor>] [--message-id <message_id>] [--to <target>] [--provider <provider>] [--run-id <run_id>] [--logs-lines <n>] [--json]
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

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for part in sys.argv[2].split("."):
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

extract_first_json_from_file() {
  python3 - "$1" <<'PY'
import json
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
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
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload
for part in sys.argv[2].split('.'):
    if not part:
        continue
    if isinstance(value, list):
        value = value[int(part)]
    elif isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
        break
if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=True))
else:
    print(value)
PY
}

run_capture() {
  local output_path="$1"
  shift
  set +e
  (cd "$REPO_ROOT" && "$@") >"$output_path" 2>&1
  local exit_code="$?"
  set -e
  printf '%s' "$exit_code"
}

append_report() {
  python3 - "$REPORT_PATH" "$@" <<'PY'
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
with report_path.open("a", encoding="utf-8") as fh:
    for line in sys.argv[2:]:
        fh.write(line + "\n")
PY
}

task_id="${1:-}"
shift || true

actor="task-reconcile-whatsapp-provider-delivery"
message_id=""
to=""
provider=""
run_id=""
logs_lines="200"
output_json="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --actor)
      shift
      actor="${1:-}"
      ;;
    --message-id)
      shift
      message_id="${1:-}"
      ;;
    --to)
      shift
      to="${1:-}"
      ;;
    --provider)
      shift
      provider="${1:-}"
      ;;
    --run-id)
      shift
      run_id="${1:-}"
      ;;
    --logs-lines)
      shift
      logs_lines="${1:-}"
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

if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

if ! [[ "$logs_lines" =~ ^[0-9]+$ ]]; then
  fatal "logs-lines invalido: $logs_lines"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

mkdir -p "$OUTBOX_DIR"

task_state="$(task_field "$task_id" delivery.whatsapp.current_state)"
task_state_before="$task_state"
tracked_message_id="$(task_field "$task_id" delivery.whatsapp.tracked_message_id)"
tracked_to="$(task_field "$task_id" delivery.whatsapp.to)"
tracked_provider="$(task_field "$task_id" delivery.whatsapp.provider)"
tracked_run_id="$(task_field "$task_id" delivery.whatsapp.run_id)"
provider_delivery_status_before="$(task_field "$task_id" delivery.whatsapp.provider_delivery_status)"
provider_delivery_reason_before="$(task_field "$task_id" delivery.whatsapp.provider_delivery_reason)"

message_id="${message_id:-$tracked_message_id}"
to="${to:-$tracked_to}"
provider="${provider:-$tracked_provider}"
run_id="${run_id:-$tracked_run_id}"
provider="${provider:-openclaw-whatsapp}"

report_run_id="$(python3 - <<'PY'
import datetime
import uuid
print(f"run-{datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{uuid.uuid4().hex[:8]}")
PY
)"
REPORT_PATH="$OUTBOX_DIR/${report_run_id}-whatsapp-provider-post-send-reconciliation.md"
REPORT_REL="${REPORT_PATH#$REPO_ROOT/}"

generate_header() {
  cat >"$REPORT_PATH" <<EOF2
# WhatsApp Provider Post-Send Reconciliation

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT
task_id: $task_id

This report captures the repo-local post-send reconciliation attempt for WhatsApp
provider proof after a gateway-accepted live send.
EOF2
}

generate_header

if [ -z "$message_id" ]; then
  summary_json="$(python3 - "$task_id" "$task_state" "$provider_delivery_status_before" "$provider_delivery_reason_before" "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "task_id": sys.argv[1],
    "message_id": "",
    "to": "",
    "provider": "",
    "task_whatsapp_state": sys.argv[2],
    "provider_delivery_status": sys.argv[3],
    "provider_delivery_reason": sys.argv[4],
    "reconciliation_status": "BLOCKED",
    "resolution": "none",
    "dominant_blocker": "whatsapp_message_id_missing_for_reconciliation",
    "capabilities_surface": "unavailable",
    "message_read_surface": "unavailable",
    "logs_surface": "unavailable",
    "report_path": sys.argv[5],
}, ensure_ascii=True))
PY
)"
  append_report "" "## Result" "- reconciliation_status: BLOCKED" "- dominant_blocker: whatsapp_message_id_missing_for_reconciliation" "- note: the task has no tracked WhatsApp message_id to reconcile post-send provider proof against"
  ./scripts/task_add_artifact.sh "$task_id" whatsapp-provider-post-send-reconciliation-report "$REPORT_REL" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$task_id" whatsapp-provider-post-send-reconciliation 2 "post-send reconciliation stayed blocked because the task has no tracked message_id" >/dev/null
  if [ "$output_json" = "1" ]; then
    printf '%s\n' "$summary_json"
  else
    printf 'TASK_WHATSAPP_PROVIDER_RECONCILIATION_BLOCKED %s report=%s reason=whatsapp_message_id_missing_for_reconciliation\n' "$task_id" "$REPORT_PATH"
  fi
  exit 2
fi

if [ "$task_state" = "delivered" ] || [ "$task_state" = "verified_by_user" ]; then
  summary_json="$(python3 - "$task_id" "$message_id" "$to" "$provider" "$task_state" "$provider_delivery_status_before" "$provider_delivery_reason_before" "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "task_id": sys.argv[1],
    "message_id": sys.argv[2],
    "to": sys.argv[3],
    "provider": sys.argv[4],
    "task_whatsapp_state": sys.argv[5],
    "provider_delivery_status": sys.argv[6],
    "provider_delivery_reason": sys.argv[7],
    "reconciliation_status": "PASS",
    "resolution": "already_final",
    "dominant_blocker": "none",
    "capabilities_surface": "not_checked",
    "message_read_surface": "not_checked",
    "logs_surface": "not_checked",
    "report_path": sys.argv[8],
}, ensure_ascii=True))
PY
)"
  append_report "" "## Result" "- reconciliation_status: PASS" "- resolution: already_final" "- note: the task already holds delivered-level provider proof before this reconciliation attempt"
  ./scripts/task_add_artifact.sh "$task_id" whatsapp-provider-post-send-reconciliation-report "$REPORT_REL" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$task_id" whatsapp-provider-post-send-reconciliation 0 "post-send reconciliation found that the task was already at delivered-level WhatsApp truth" >/dev/null
  if [ "$output_json" = "1" ]; then
    printf '%s\n' "$summary_json"
  else
    printf 'TASK_WHATSAPP_PROVIDER_RECONCILIATION_OK %s report=%s resolution=already_final\n' "$task_id" "$REPORT_PATH"
  fi
  exit 0
fi

cap_output_file="$(mktemp)"
read_output_file="$(mktemp)"
logs_output_file="$(mktemp)"
trap 'rm -f "$cap_output_file" "$read_output_file" "$logs_output_file"' EXIT

cap_exit="$(run_capture "$cap_output_file" openclaw channels capabilities --channel whatsapp --json)"
read_exit=""
if [ -n "$to" ]; then
  read_exit="$(run_capture "$read_output_file" openclaw message read --channel whatsapp --target "$to" --around "$message_id" --json)"
else
  printf 'no tracked target was available for message read\n' >"$read_output_file"
  read_exit="2"
fi
logs_exit="$(run_capture "$logs_output_file" openclaw channels logs --channel whatsapp --json --lines "$logs_lines")"

cap_json="$(extract_first_json_from_file "$cap_output_file")"
read_json="$(extract_first_json_from_file "$read_output_file")"
logs_json="$(extract_first_json_from_file "$logs_output_file")"

analysis_json="$(python3 - "$message_id" "$to" "$cap_exit" "$cap_json" "$read_exit" "$read_json" "$logs_exit" "$logs_json" "$read_output_file" "$logs_output_file" <<'PY'
import json
import pathlib
import re
import sys

message_id = sys.argv[1]
target = sys.argv[2]
cap_exit = int(sys.argv[3]) if sys.argv[3] else 1
cap_json_raw = sys.argv[4]
read_exit = int(sys.argv[5]) if sys.argv[5] else 1
read_json_raw = sys.argv[6]
logs_exit = int(sys.argv[7]) if sys.argv[7] else 1
logs_json_raw = sys.argv[8]
read_output_text = pathlib.Path(sys.argv[9]).read_text(encoding="utf-8", errors="replace")
logs_output_text = pathlib.Path(sys.argv[10]).read_text(encoding="utf-8", errors="replace")

cap_payload = json.loads(cap_json_raw) if cap_json_raw else {}
read_payload = json.loads(read_json_raw) if read_json_raw else {}
logs_payload = json.loads(logs_json_raw) if logs_json_raw else {}

result = {
    "capabilities_surface": "unavailable",
    "capabilities_note": "the runtime did not return machine-readable channel capabilities",
    "message_read_surface": "unavailable",
    "message_read_note": "the runtime did not expose a readable WhatsApp message read surface",
    "message_read_signal": "none",
    "message_read_status": "",
    "message_read_reason": "",
    "message_read_match_excerpt": "",
    "logs_surface": "unavailable",
    "logs_note": "the runtime did not expose readable WhatsApp channel logs",
    "logs_signal": "none",
    "logs_status": "",
    "logs_reason": "",
    "logs_match_excerpt": "",
}

recon_actions = {"read", "status", "receipt", "receipts", "history", "lookup", "get", "events"}
channels = cap_payload.get("channels") or []
if cap_exit == 0 and channels:
    actions = []
    for entry in channels:
        if entry.get("channel") == "whatsapp":
            actions = [str(action).lower() for action in (entry.get("actions") or [])]
            break
    if actions:
        if any(action in recon_actions for action in actions):
            result["capabilities_surface"] = "canonical_usable"
            result["capabilities_note"] = f"channel capabilities advertise WhatsApp reconciliation-oriented actions: {','.join(actions)}"
        else:
            result["capabilities_surface"] = "present_but_non_canonical"
            result["capabilities_note"] = f"channel capabilities are readable but only advertise {','.join(actions)}, with no message status/receipt action"
    else:
        result["capabilities_surface"] = "ambiguous"
        result["capabilities_note"] = "channel capabilities returned no WhatsApp action list"

read_text_lower = read_output_text.lower()
if not target:
    result["message_read_surface"] = "unavailable"
    result["message_read_note"] = "the task has no tracked target for a message read probe"
elif read_exit != 0 and "not supported" in read_text_lower:
    result["message_read_surface"] = "unavailable"
    result["message_read_note"] = "openclaw message read is not supported for WhatsApp in the current runtime"
elif read_exit == 0 and read_payload:
    result["message_read_surface"] = "ambiguous"
    result["message_read_note"] = "the runtime returned a machine-readable message read payload, but no strong provider proof was matched yet"
else:
    result["message_read_surface"] = "ambiguous"
    result["message_read_note"] = "the runtime returned a non-standard WhatsApp read result that does not classify cleanly"

matched_records = []

def walk(value, path):
    if isinstance(value, dict):
        record_id = value.get("messageId") or value.get("message_id") or value.get("id") or value.get("providerMessageId")
        if record_id and str(record_id) == message_id:
            matched_records.append({"path": path, "record": value})
        for key, child in value.items():
            walk(child, path + [str(key)])
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk(child, path + [str(index)])

walk(read_payload, [])

strong_delivered = {"delivered", "read", "read_by_recipient", "provider_delivered", "delivery_confirmed"}
strong_failed = {"failed", "error", "undeliverable", "bounced", "provider_failed"}
ambiguous = {"pending", "queued", "sent", "submitted", "accepted", "accepted_by_gateway", "processing"}

for item in matched_records:
    record = item["record"]
    for key in ("status", "state", "deliveryStatus", "delivery_status", "providerStatus", "provider_status", "ack"):
        if key not in record:
            continue
        value = str(record.get(key, "")).strip().lower()
        excerpt = json.dumps(record, ensure_ascii=True)[:240]
        if value in strong_delivered:
            result["message_read_surface"] = "canonical_usable"
            result["message_read_signal"] = "delivered"
            result["message_read_status"] = value
            result["message_read_reason"] = "the WhatsApp read payload matched the tracked message_id with an explicit delivered/read status"
            result["message_read_match_excerpt"] = excerpt
            break
        if value in strong_failed:
            result["message_read_surface"] = "canonical_usable"
            result["message_read_signal"] = "failed"
            result["message_read_status"] = value
            result["message_read_reason"] = "the WhatsApp read payload matched the tracked message_id with an explicit failed status"
            result["message_read_match_excerpt"] = excerpt
            break
        if value in ambiguous:
            result["message_read_surface"] = "ambiguous"
            result["message_read_signal"] = "ambiguous"
            result["message_read_status"] = value
            result["message_read_reason"] = "the WhatsApp read payload matched the tracked message_id but only exposed an ambiguous provider status"
            result["message_read_match_excerpt"] = excerpt
            break
    if result["message_read_signal"] != "none":
        break

log_lines = logs_payload.get("lines") or []
matched_lines = []
for entry in log_lines:
    message = str(entry.get("message", ""))
    if message_id in message:
        matched_lines.append(message)

if logs_exit == 0 and log_lines:
    if matched_lines:
        result["logs_surface"] = "ambiguous"
        result["logs_note"] = "channel logs are readable and can be correlated by message_id"
    else:
        result["logs_surface"] = "ambiguous"
        result["logs_note"] = "channel logs are readable, but the tracked message_id did not appear in the sampled window"

for line in matched_lines:
    line_lower = line.lower()
    excerpt = re.sub(r"\s+", " ", line).strip()[:240]
    if re.search(r"\b(delivered|read|receipt|delivery confirmed)\b", line_lower):
        result["logs_surface"] = "canonical_usable"
        result["logs_signal"] = "delivered"
        result["logs_status"] = "provider_delivery_proved"
        result["logs_reason"] = "channel logs matched the tracked message_id with explicit delivered/read wording"
        result["logs_match_excerpt"] = excerpt
        break
    if re.search(r"\b(failed|error|undeliverable|bounced)\b", line_lower):
        result["logs_surface"] = "canonical_usable"
        result["logs_signal"] = "failed"
        result["logs_status"] = "provider_failed"
        result["logs_reason"] = "channel logs matched the tracked message_id with explicit failure wording"
        result["logs_match_excerpt"] = excerpt
        break
    if re.search(r"\b(sent message|sending message|queued|pending|accepted)\b", line_lower):
        result["logs_surface"] = "ambiguous"
        result["logs_signal"] = "gateway_only"
        result["logs_status"] = "gateway_accepted"
        result["logs_reason"] = "channel logs only proved the outbound send/ack for the tracked message_id"
        result["logs_match_excerpt"] = excerpt

print(json.dumps(result, ensure_ascii=True))
PY
)"

capabilities_surface="$(json_field "$analysis_json" capabilities_surface)"
capabilities_note="$(json_field "$analysis_json" capabilities_note)"
message_read_surface="$(json_field "$analysis_json" message_read_surface)"
message_read_note="$(json_field "$analysis_json" message_read_note)"
message_read_signal="$(json_field "$analysis_json" message_read_signal)"
message_read_status="$(json_field "$analysis_json" message_read_status)"
message_read_reason="$(json_field "$analysis_json" message_read_reason)"
message_read_match_excerpt="$(json_field "$analysis_json" message_read_match_excerpt)"
logs_surface="$(json_field "$analysis_json" logs_surface)"
logs_note="$(json_field "$analysis_json" logs_note)"
logs_signal="$(json_field "$analysis_json" logs_signal)"
logs_status="$(json_field "$analysis_json" logs_status)"
logs_reason="$(json_field "$analysis_json" logs_reason)"
logs_match_excerpt="$(json_field "$analysis_json" logs_match_excerpt)"

reconciliation_status="BLOCKED"
resolution="none"
dominant_blocker="whatsapp_post_send_provider_proof_surface_missing"
result_note="the runtime still exposes no strong provider-proof reconciliation surface after gateway acceptance"

provider_delivery_status_after="$provider_delivery_status_before"
provider_delivery_reason_after="$provider_delivery_reason_before"

if [ "$message_read_signal" = "delivered" ]; then
  ./scripts/task_record_whatsapp_provider_delivery.sh \
    "$task_id" \
    "$actor" \
    "$provider" \
    "$to" \
    "$message_id" \
    delivered \
    "$(sanitize_excerpt "${message_read_match_excerpt:-$message_read_reason}")" \
    --run-id "$run_id" \
    --provider-status "${message_read_status:-provider_delivered}" \
    --reason "${message_read_reason:-the runtime exposed post-send provider delivery proof through message read}" \
    --normalized-evidence-json "{\"surface\":\"message_read\",\"message_id\":\"$message_id\",\"status\":\"${message_read_status:-provider_delivered}\"}" >/dev/null
  reconciliation_status="PASS"
  resolution="delivered"
  dominant_blocker="none"
  result_note="the runtime exposed strong provider delivery proof through the WhatsApp message read surface"
elif [ "$logs_signal" = "delivered" ]; then
  ./scripts/task_record_whatsapp_provider_delivery.sh \
    "$task_id" \
    "$actor" \
    "$provider" \
    "$to" \
    "$message_id" \
    delivered \
    "$(sanitize_excerpt "${logs_match_excerpt:-$logs_reason}")" \
    --run-id "$run_id" \
    --provider-status "${logs_status:-provider_delivered}" \
    --reason "${logs_reason:-the runtime exposed post-send provider delivery proof through channel logs}" \
    --normalized-evidence-json "{\"surface\":\"channel_logs\",\"message_id\":\"$message_id\",\"status\":\"${logs_status:-provider_delivered}\"}" >/dev/null
  reconciliation_status="PASS"
  resolution="delivered"
  dominant_blocker="none"
  result_note="the runtime exposed strong provider delivery proof through the WhatsApp channel logs"
elif [ "$message_read_signal" = "ambiguous" ]; then
  if [ "$task_state" = "accepted_by_gateway" ]; then
    ./scripts/task_record_whatsapp_provider_delivery.sh \
      "$task_id" \
      "$actor" \
      "$provider" \
      "$to" \
      "$message_id" \
      ambiguous \
      "$(sanitize_excerpt "${message_read_match_excerpt:-$message_read_reason}")" \
      --run-id "$run_id" \
      --provider-status "${message_read_status:-provider_delivery_unproved}" \
      --reason "${message_read_reason:-the runtime exposed only ambiguous provider evidence through message read}" \
      --normalized-evidence-json "{\"surface\":\"message_read\",\"message_id\":\"$message_id\",\"status\":\"${message_read_status:-provider_delivery_unproved}\"}" >/dev/null
    task_state="provider_delivery_unproved"
  fi
  dominant_blocker="whatsapp_post_send_provider_proof_ambiguous"
  result_note="the runtime exposed a post-send surface, but it stayed ambiguous and could not prove delivery"
fi

provider_delivery_status_after="$(task_field "$task_id" delivery.whatsapp.provider_delivery_status)"
provider_delivery_reason_after="$(task_field "$task_id" delivery.whatsapp.provider_delivery_reason)"
task_state_after="$(task_field "$task_id" delivery.whatsapp.current_state)"

append_report \
  "" \
  "## Task Context" \
  "- task_state_before: ${task_state_before}" \
  "- task_state_after: ${task_state_after}" \
  "- tracked_message_id: ${message_id}" \
  "- tracked_target: ${to:-'(none)'}" \
  "- tracked_provider: ${provider}" \
  "- tracked_run_id: ${run_id:-'(none)'}"

append_report \
  "" \
  "## Surface Classification" \
  "- capabilities_surface: ${capabilities_surface}" \
  "- capabilities_note: ${capabilities_note}" \
  "- message_read_surface: ${message_read_surface}" \
  "- message_read_note: ${message_read_note}" \
  "- logs_surface: ${logs_surface}" \
  "- logs_note: ${logs_note}"

if [ -n "$message_read_match_excerpt" ]; then
  append_report "- message_read_match_excerpt: ${message_read_match_excerpt}"
fi
if [ -n "$logs_match_excerpt" ]; then
  append_report "- logs_match_excerpt: ${logs_match_excerpt}"
fi

append_report \
  "" \
  "## Result" \
  "- reconciliation_status: ${reconciliation_status}" \
  "- resolution: ${resolution}" \
  "- dominant_blocker: ${dominant_blocker}" \
  "- provider_delivery_status: ${provider_delivery_status_after}" \
  "- provider_delivery_reason: ${provider_delivery_reason_after}" \
  "- note: ${result_note}" \
  "- sampled_commands:" \
  "  - openclaw channels capabilities --channel whatsapp --json" \
  "  - openclaw message read --channel whatsapp --target ${to:-'(missing-target)'} --around ${message_id} --json" \
  "  - openclaw channels logs --channel whatsapp --json --lines ${logs_lines}"

summary_json="$(python3 - "$task_id" "$message_id" "$to" "$provider" "$task_state_after" "$provider_delivery_status_after" "$provider_delivery_reason_after" "$reconciliation_status" "$resolution" "$dominant_blocker" "$capabilities_surface" "$message_read_surface" "$logs_surface" "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "task_id": sys.argv[1],
    "message_id": sys.argv[2],
    "to": sys.argv[3],
    "provider": sys.argv[4],
    "task_whatsapp_state": sys.argv[5],
    "provider_delivery_status": sys.argv[6],
    "provider_delivery_reason": sys.argv[7],
    "reconciliation_status": sys.argv[8],
    "resolution": sys.argv[9],
    "dominant_blocker": sys.argv[10],
    "capabilities_surface": sys.argv[11],
    "message_read_surface": sys.argv[12],
    "logs_surface": sys.argv[13],
    "report_path": sys.argv[14],
}, ensure_ascii=True))
PY
)"

./scripts/task_add_artifact.sh "$task_id" whatsapp-provider-post-send-reconciliation-report "$REPORT_REL" >/dev/null
TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$task_id" whatsapp-provider-post-send-reconciliation "$([ "$reconciliation_status" = "PASS" ] && printf '0' || printf '2')" "$result_note" >/dev/null

trap - EXIT
rm -f "$cap_output_file" "$read_output_file" "$logs_output_file"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$summary_json"
else
  case "$reconciliation_status" in
    PASS)
      printf 'TASK_WHATSAPP_PROVIDER_RECONCILIATION_OK %s report=%s resolution=%s\n' "$task_id" "$REPORT_PATH" "$resolution"
      ;;
    *)
      printf 'TASK_WHATSAPP_PROVIDER_RECONCILIATION_BLOCKED %s report=%s reason=%s\n' "$task_id" "$REPORT_PATH" "$dominant_blocker"
      ;;
  esac
fi

if [ "$reconciliation_status" = "PASS" ]; then
  exit 0
fi
exit 2
