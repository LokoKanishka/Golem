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
    "message_status_surface": "unavailable",
    "message_status_found": "unknown",
    "message_status_current": "",
    "message_status_strongest": "",
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
    "message_status_surface": "not_checked",
    "message_status_found": "unknown",
    "message_status_current": "",
    "message_status_strongest": "",
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
status_output_file="$(mktemp)"
logs_output_file="$(mktemp)"
trap 'rm -f "$cap_output_file" "$status_output_file" "$logs_output_file"' EXIT

cap_exit="$(run_capture "$cap_output_file" openclaw channels capabilities --channel whatsapp --json)"
status_exit="$(run_capture "$status_output_file" openclaw message status --channel whatsapp --id "$message_id" --json)"
logs_exit="$(run_capture "$logs_output_file" openclaw channels logs --channel whatsapp --json --lines "$logs_lines")"

cap_json="$(extract_first_json_from_file "$cap_output_file")"
status_json="$(extract_first_json_from_file "$status_output_file")"
logs_json="$(extract_first_json_from_file "$logs_output_file")"

analysis_json="$(python3 - "$message_id" "$cap_exit" "$cap_json" "$status_exit" "$status_json" "$logs_exit" "$logs_json" "$status_output_file" "$logs_output_file" <<'PY'
import json
import pathlib
import re
import sys

message_id = sys.argv[1]
cap_exit = int(sys.argv[2]) if sys.argv[2] else 1
cap_json_raw = sys.argv[3]
status_exit = int(sys.argv[4]) if sys.argv[4] else 1
status_json_raw = sys.argv[5]
logs_exit = int(sys.argv[6]) if sys.argv[6] else 1
logs_json_raw = sys.argv[7]
status_output_text = pathlib.Path(sys.argv[8]).read_text(encoding="utf-8", errors="replace")
logs_output_text = pathlib.Path(sys.argv[9]).read_text(encoding="utf-8", errors="replace")

cap_payload = json.loads(cap_json_raw) if cap_json_raw else {}
status_payload = json.loads(status_json_raw) if status_json_raw else {}
logs_payload = json.loads(logs_json_raw) if logs_json_raw else {}

def normalize_status(value):
    if value is None:
        return ""
    text = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "delivery_ack": "delivered",
        "read_by_recipient": "read",
        "provider_delivered": "delivered",
    }
    return aliases.get(text, text)

result = {
    "capabilities_surface": "unavailable",
    "capabilities_note": "the runtime did not return machine-readable channel capabilities",
    "message_status_surface": "unavailable",
    "message_status_note": "the runtime did not return a machine-readable WhatsApp message status payload",
    "message_status_signal": "none",
    "message_status_found": "unknown",
    "message_status_current": "",
    "message_status_strongest": "",
    "message_status_reason": "",
    "message_status_match_excerpt": "",
    "logs_surface": "unavailable",
    "logs_note": "the runtime did not expose readable WhatsApp channel logs",
    "logs_signal": "none",
    "logs_status": "",
    "logs_reason": "",
    "logs_match_excerpt": "",
}

recon_actions = {"status", "lookup", "receipt", "receipts", "history", "get", "events"}
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
            result["capabilities_note"] = f"channel capabilities are readable but only advertise {','.join(actions)}, with no status/lookup action"
    else:
        result["capabilities_surface"] = "ambiguous"
        result["capabilities_note"] = "channel capabilities returned no WhatsApp action list"

status_text_lower = status_output_text.lower()
if status_exit == 0 and status_payload:
    found_raw = status_payload.get("found")
    current = normalize_status(status_payload.get("currentStatus") or status_payload.get("current_status"))
    strongest = normalize_status(
        status_payload.get("strongestStatus") or status_payload.get("strongest_status")
    )
    result["message_status_surface"] = "canonical_usable"
    result["message_status_found"] = "true" if found_raw is True else "false" if found_raw is False else "unknown"
    result["message_status_current"] = current
    result["message_status_strongest"] = strongest
    result["message_status_match_excerpt"] = json.dumps(status_payload, ensure_ascii=True)[:240]
    if found_raw is False:
        result["message_status_note"] = "the canonical WhatsApp message status surface is available but did not find the tracked message_id"
        result["message_status_reason"] = "the canonical status surface returned found=false for the tracked message_id"
    elif found_raw is True:
        result["message_status_note"] = "the canonical WhatsApp message status surface returned a persisted status entry for the tracked message_id"
        strong_statuses = {"delivered", "read", "played"}
        ambiguous_statuses = {"sent", "server_ack"}
        decisive = strongest or current
        if decisive in strong_statuses:
            result["message_status_signal"] = "delivered"
            result["message_status_reason"] = f"the canonical status surface returned strongestStatus={decisive}"
        elif decisive in ambiguous_statuses:
            result["message_status_surface"] = "ambiguous"
            result["message_status_signal"] = "ambiguous"
            result["message_status_reason"] = f"the canonical status surface returned strongestStatus={decisive}, which is still below delivered/read"
        else:
            result["message_status_surface"] = "ambiguous"
            result["message_status_reason"] = "the canonical status surface returned the tracked message_id, but without a decisive post-send status"
    else:
        result["message_status_surface"] = "ambiguous"
        result["message_status_note"] = "the canonical WhatsApp message status surface returned a payload without a clear found flag"
        result["message_status_reason"] = "the canonical status payload did not classify cleanly"
elif status_exit != 0 and "message status lookup is only supported for channel whatsapp" in status_text_lower:
    result["message_status_surface"] = "unavailable"
    result["message_status_note"] = "the runtime rejected WhatsApp message status lookup"
elif status_exit != 0:
    result["message_status_surface"] = "unavailable"
    result["message_status_note"] = "the runtime did not complete the canonical WhatsApp message status lookup cleanly"
else:
    result["message_status_surface"] = "ambiguous"
    result["message_status_note"] = "the runtime returned a non-standard WhatsApp status result that does not classify cleanly"

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
        result["logs_surface"] = "supporting_only"
        result["logs_signal"] = "delivered"
        result["logs_status"] = "provider_delivery_proved"
        result["logs_reason"] = "channel logs matched the tracked message_id with explicit delivered/read wording, but logs are no longer the primary reconciliation surface"
        result["logs_match_excerpt"] = excerpt
        break
    if re.search(r"\b(failed|error|undeliverable|bounced)\b", line_lower):
        result["logs_surface"] = "supporting_only"
        result["logs_signal"] = "failed"
        result["logs_status"] = "provider_failed"
        result["logs_reason"] = "channel logs matched the tracked message_id with explicit failure wording"
        result["logs_match_excerpt"] = excerpt
        break
    if re.search(r"\b(sent message|sending message|queued|pending|accepted|server_ack)\b", line_lower):
        result["logs_surface"] = "ambiguous"
        result["logs_signal"] = "ambiguous"
        result["logs_status"] = "provider_delivery_unproved"
        result["logs_reason"] = "channel logs only proved outbound send or an intermediate ack for the tracked message_id"
        result["logs_match_excerpt"] = excerpt

print(json.dumps(result, ensure_ascii=True))
PY
)"

capabilities_surface="$(json_field "$analysis_json" capabilities_surface)"
capabilities_note="$(json_field "$analysis_json" capabilities_note)"
message_status_surface="$(json_field "$analysis_json" message_status_surface)"
message_status_note="$(json_field "$analysis_json" message_status_note)"
message_status_signal="$(json_field "$analysis_json" message_status_signal)"
message_status_found="$(json_field "$analysis_json" message_status_found)"
message_status_current="$(json_field "$analysis_json" message_status_current)"
message_status_strongest="$(json_field "$analysis_json" message_status_strongest)"
message_status_reason="$(json_field "$analysis_json" message_status_reason)"
message_status_match_excerpt="$(json_field "$analysis_json" message_status_match_excerpt)"
logs_surface="$(json_field "$analysis_json" logs_surface)"
logs_note="$(json_field "$analysis_json" logs_note)"
logs_signal="$(json_field "$analysis_json" logs_signal)"
logs_status="$(json_field "$analysis_json" logs_status)"
logs_reason="$(json_field "$analysis_json" logs_reason)"
logs_match_excerpt="$(json_field "$analysis_json" logs_match_excerpt)"

reconciliation_status="BLOCKED"
resolution="none"
dominant_blocker="whatsapp_canonical_status_surface_missing"
result_note="the canonical WhatsApp status surface did not yet expose strong provider proof after gateway acceptance"

provider_delivery_status_after="$provider_delivery_status_before"
provider_delivery_reason_after="$provider_delivery_reason_before"

if [ "$message_status_signal" = "delivered" ]; then
  ./scripts/task_record_whatsapp_provider_delivery.sh \
    "$task_id" \
    "$actor" \
    "$provider" \
    "$to" \
    "$message_id" \
    delivered \
    "$(sanitize_excerpt "${message_status_match_excerpt:-$message_status_reason}")" \
    --run-id "$run_id" \
    --provider-status "${message_status_strongest:-provider_delivered}" \
    --reason "${message_status_reason:-the runtime exposed strong provider delivery proof through the canonical message status surface}" \
    --normalized-evidence-json "{\"surface\":\"message_status\",\"message_id\":\"$message_id\",\"found\":\"${message_status_found}\",\"current_status\":\"${message_status_current}\",\"strongest_status\":\"${message_status_strongest}\"}" >/dev/null
  reconciliation_status="PASS"
  resolution="delivered"
  dominant_blocker="none"
  result_note="the canonical WhatsApp message status surface exposed strong provider proof for the tracked message_id"
elif [ "$message_status_signal" = "ambiguous" ]; then
  if [ "$task_state" = "accepted_by_gateway" ]; then
    ./scripts/task_record_whatsapp_provider_delivery.sh \
      "$task_id" \
      "$actor" \
      "$provider" \
      "$to" \
      "$message_id" \
      ambiguous \
      "$(sanitize_excerpt "${message_status_match_excerpt:-$message_status_reason}")" \
      --run-id "$run_id" \
      --provider-status "${message_status_strongest:-provider_delivery_unproved}" \
      --reason "${message_status_reason:-the canonical message status surface only exposed an intermediate provider status}" \
      --normalized-evidence-json "{\"surface\":\"message_status\",\"message_id\":\"$message_id\",\"found\":\"${message_status_found}\",\"current_status\":\"${message_status_current}\",\"strongest_status\":\"${message_status_strongest}\"}" >/dev/null
    task_state="provider_delivery_unproved"
  fi
  if [ "$message_status_strongest" = "server_ack" ] || [ "$message_status_current" = "server_ack" ]; then
    dominant_blocker="whatsapp_canonical_status_only_server_ack"
    result_note="the canonical WhatsApp status surface returned only server_ack, which is still below delivered/read"
  else
    dominant_blocker="whatsapp_canonical_status_only_sent"
    result_note="the canonical WhatsApp status surface returned only sent-level evidence, which is still below delivered/read"
  fi
elif [ "$message_status_surface" = "canonical_usable" ] && [ "$message_status_found" = "false" ]; then
  dominant_blocker="whatsapp_canonical_status_message_id_not_found"
  result_note="the canonical WhatsApp status surface is available but did not find the tracked message_id"
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
  "- message_status_surface: ${message_status_surface}" \
  "- message_status_note: ${message_status_note}" \
  "- message_status_found: ${message_status_found}" \
  "- message_status_current: ${message_status_current:-'(none)'}" \
  "- message_status_strongest: ${message_status_strongest:-'(none)'}" \
  "- logs_surface: ${logs_surface}" \
  "- logs_note: ${logs_note}"

if [ -n "$message_status_match_excerpt" ]; then
  append_report "- message_status_match_excerpt: ${message_status_match_excerpt}"
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
  "  - openclaw message status --channel whatsapp --id ${message_id} --json" \
  "  - openclaw channels logs --channel whatsapp --json --lines ${logs_lines}"

summary_json="$(python3 - "$task_id" "$message_id" "$to" "$provider" "$task_state_after" "$provider_delivery_status_after" "$provider_delivery_reason_after" "$reconciliation_status" "$resolution" "$dominant_blocker" "$capabilities_surface" "$message_status_surface" "$message_status_found" "$message_status_current" "$message_status_strongest" "$logs_surface" "$REPORT_PATH" <<'PY'
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
    "message_status_surface": sys.argv[12],
    "message_status_found": sys.argv[13],
    "message_status_current": sys.argv[14],
    "message_status_strongest": sys.argv[15],
    "logs_surface": sys.argv[16],
    "report_path": sys.argv[17],
}, ensure_ascii=True))
PY
)"

./scripts/task_add_artifact.sh "$task_id" whatsapp-provider-post-send-reconciliation-report "$REPORT_REL" >/dev/null
TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$task_id" whatsapp-provider-post-send-reconciliation "$([ "$reconciliation_status" = "PASS" ] && printf '0' || printf '2')" "$result_note" >/dev/null

trap - EXIT
rm -f "$cap_output_file" "$status_output_file" "$logs_output_file"

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
