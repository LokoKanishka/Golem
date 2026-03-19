#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
TIMESTAMP="$(
  python3 - <<'PY'
import datetime
print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
PY
)"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-live-provider-canary.md"
TASK_ID=""

mkdir -p "$OUTBOX_DIR"

run_cmd() {
  local label="$1"
  local cmd="$2"
  local output
  local exit_code

  printf '\n## %s\n' "$label"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf 'exit_code: %s\n' "$exit_code"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

extract_task_id() {
  printf '%s\n' "$1" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json
}

extract_report_path() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'^report_path: (\S+)$', text, re.MULTILINE)
if match:
    print(match.group(1))
    raise SystemExit(0)
match = re.search(r'^VERIFY_[A-Z0-9_]+_(?:OK|BLOCKED|FAIL)\b.*\breport=(\S+)', text, re.MULTILINE)
print(match.group(1) if match else "")
PY
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

task_field() {
  local task_id="$1"
  local path_expr="$2"
  python3 - "$REPO_ROOT/tasks/${task_id}.json" "$path_expr" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value = task
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

record_verify_task() {
  local final_status="$1"
  local final_note="$2"
  local summary_json="$3"
  local report_rel="${REPORT_PATH#$REPO_ROOT/}"
  local exit_code="1"

  case "$final_status" in
    PASS) exit_code="0" ;;
    BLOCKED) exit_code="2" ;;
  esac

  ./scripts/task_add_artifact.sh "$TASK_ID" whatsapp-live-provider-canary-report "$report_rel" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$(python3 - "$summary_json" "$report_rel" <<'PY'
import json
import sys
print(json.dumps({"canary_summary": json.loads(sys.argv[1]), "report_path": sys.argv[2]}, ensure_ascii=True))
PY
)" ./scripts/task_add_output.sh "$TASK_ID" whatsapp-live-provider-canary "$exit_code" "$final_note" >/dev/null

  case "$final_status" in
    PASS) ./scripts/task_close.sh "$TASK_ID" done "$final_note" >/dev/null ;;
    BLOCKED) ./scripts/task_close.sh "$TASK_ID" blocked "$final_note" >/dev/null ;;
    *) ./scripts/task_close.sh "$TASK_ID" failed "$final_note" >/dev/null ;;
  esac
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Live Provider Canary Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report answers one operational question:

Can the repo execute a controlled live WhatsApp send and persist real provider proof
strong enough to raise the canonical WhatsApp lane to delivered or higher?
EOF
}

generate_header

printf '# WhatsApp Live Provider Canary Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Create Verify Task" "./scripts/task_new.sh verification-whatsapp-live-provider-canary 'Verify controlled live WhatsApp provider canary'"
TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
if [ -z "$TASK_ID" ]; then
  printf 'VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_FAIL report=%s task=(missing) reason=task_creation_failed\n' "$REPORT_PATH" >&2
  exit 1
fi

run_cmd "Move Verify Task To Running" "./scripts/task_update.sh $TASK_ID running"
run_cmd "Resolve Canary Target" "./scripts/resolve_whatsapp_canary_target.sh --json"
target_json="$LAST_OUTPUT"
target_exit="$LAST_EXIT_CODE"
canary_target="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("target", ""))
except Exception:
    print("")
PY
)"
target_source="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("source", ""))
except Exception:
    print("")
PY
)"
target_note="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("note", ""))
except Exception:
    print("")
PY
)"

if [ "$target_exit" -ne 0 ] || [ -z "$canary_target" ]; then
  final_status="BLOCKED"
  final_note="no canonical safe WhatsApp canary target is currently resolvable from env or runtime allowlist"
  summary_json="$(python3 - <<'PY'
import json
print(json.dumps({"target_resolved": False, "canary_target": "", "target_source": "", "wrapper_status": "", "whatsapp_state": ""}, ensure_ascii=True))
PY
)"
  append_report "" "## Canary Resolution" "- verify_status: BLOCKED" "- note: ${final_note}" "- target_output:" '```text' "$target_json" '```'
  record_verify_task "$final_status" "$final_note" "$summary_json"
  printf 'report_path: %s\n' "$REPORT_PATH"
  printf 'VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_BLOCKED task=%s report=%s reason=canary_target_unresolved\n' "$TASK_ID" "$REPORT_PATH"
  exit 2
fi

run_cmd "Delivery submitted" "./scripts/task_record_delivery_transition.sh $TASK_ID submitted verify-whatsapp-live-provider-canary whatsapp 'controlled live WhatsApp canary requested a real outbound send'"
run_cmd "Delivery accepted" "./scripts/task_record_delivery_transition.sh $TASK_ID accepted verify-whatsapp-live-provider-canary whatsapp 'controlled live WhatsApp canary entered the outbound lane locally'"
run_cmd "Delivery delivered" "./scripts/task_record_delivery_transition.sh $TASK_ID delivered verify-whatsapp-live-provider-canary whatsapp 'generic delivery lane is ready while channel truth still depends on provider proof'"
run_cmd "Delivery visible" "./scripts/task_record_delivery_transition.sh $TASK_ID visible verify-whatsapp-live-provider-canary whatsapp 'generic claim now depends on the canonical WhatsApp provider-proof lane'"

canary_message="GOLEM-211 live provider canary ${TIMESTAMP}"
run_cmd "Live Canary Send" "./scripts/task_send_whatsapp_live.sh $TASK_ID $canary_target --message '$canary_message' --actor verify-whatsapp-live-provider-canary --evidence 'controlled live provider canary send' --json"
wrapper_output="$LAST_OUTPUT"
wrapper_exit="$LAST_EXIT_CODE"
wrapper_status="$(python3 - "$wrapper_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("wrapper_status", ""))
except Exception:
    print("")
PY
)"
wrapper_state="$(python3 - "$wrapper_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("wrapper_state", ""))
except Exception:
    print("")
PY
)"
wrapper_report="$(python3 - "$wrapper_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("report_path", ""))
except Exception:
    print("")
PY
)"

run_cmd "Claim delivered wording" "./scripts/task_claim_whatsapp_delivery.sh $TASK_ID verify-whatsapp-live-provider-canary delivered 'controlled live canary checks whether delivered wording is now honestly authorized'"
delivered_claim_output="$LAST_OUTPUT"
delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Claim generic final success" "./scripts/task_claim_user_facing_success.sh $TASK_ID verify-whatsapp-live-provider-canary whatsapp 'controlled live canary checks whether generic final success is honestly authorized' 'final success claim'"
generic_claim_output="$LAST_OUTPUT"
generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Delivery Summary" "./scripts/task_delivery_summary.sh $TASK_ID"
delivery_summary="$LAST_OUTPUT"
run_cmd "Task Summary" "./scripts/task_summary.sh $TASK_ID"
task_summary="$LAST_OUTPUT"

whatsapp_state="$(task_field "$TASK_ID" delivery.whatsapp.current_state)"
provider_delivery_status="$(task_field "$TASK_ID" delivery.whatsapp.provider_delivery_status)"
provider_delivery_reason="$(task_field "$TASK_ID" delivery.whatsapp.provider_delivery_reason)"
message_id="$(task_field "$TASK_ID" delivery.whatsapp.tracked_message_id)"

final_status="BLOCKED"
final_note="live canary executed a real send, but the current runtime response still does not prove provider delivery strongly enough"
if [ "$wrapper_exit" -eq 1 ] || [ "$wrapper_status" = "FAIL" ]; then
  final_status="FAIL"
  final_note="the live canary exposed an internal inconsistency or drift while processing the live send result"
elif [ "$whatsapp_state" = "delivered" ] || [ "$whatsapp_state" = "verified_by_user" ]; then
  if [ "$delivered_claim_exit" -eq 0 ] && [ "$generic_claim_exit" -eq 0 ]; then
    final_status="PASS"
    final_note="the live canary executed a real send and persisted strong provider proof in the canonical WhatsApp lane"
  else
    final_status="FAIL"
    final_note="the live canary reached delivered-level WhatsApp state but the claim gates did not stay coherent"
  fi
elif [ "$wrapper_exit" -eq 2 ] || [ "$wrapper_status" = "BLOCKED" ]; then
  final_status="BLOCKED"
  final_note="the live canary could not complete a coherent live send attempt under the current runtime"
elif [ "$whatsapp_state" = "accepted_by_gateway" ] || [ "$whatsapp_state" = "provider_delivery_unproved" ] || [ "$whatsapp_state" = "requested" ]; then
  if printf '%s\n' "$delivered_claim_output" | rg -q '^TASK_WHATSAPP_CLAIM_BLOCKED ' && printf '%s\n' "$generic_claim_output" | rg -q '^TASK_USER_FACING_CLAIM_BLOCKED '; then
    final_status="BLOCKED"
    final_note="the live canary sent a real WhatsApp message, but only gateway or inconclusive provider evidence was available"
  else
    final_status="FAIL"
    final_note="the live canary stayed below delivered, but one of the claim gates inflated the outcome"
  fi
else
  final_status="FAIL"
  final_note="the live canary ended in an incoherent WhatsApp state"
fi

append_report \
  "" \
  "## Live Canary Result" \
  "- task_id: ${TASK_ID}" \
  "- target: ${canary_target}" \
  "- target_source: ${target_source}" \
  "- target_note: ${target_note}" \
  "- wrapper_status: ${wrapper_status}" \
  "- wrapper_state: ${wrapper_state}" \
  "- whatsapp_state: ${whatsapp_state}" \
  "- provider_delivery_status: ${provider_delivery_status}" \
  "- provider_delivery_reason: ${provider_delivery_reason}" \
  "- message_id: ${message_id}" \
  "- final_status: ${final_status}" \
  "- final_note: ${final_note}" \
  "- wrapper_report: ${wrapper_report}" \
  "- delivery_summary:" \
  '```text' \
  "$delivery_summary" \
  '```'

summary_json="$(python3 - "$canary_target" "$target_source" "$wrapper_status" "$wrapper_state" "$whatsapp_state" "$provider_delivery_status" "$provider_delivery_reason" "$message_id" "$wrapper_report" <<'PY'
import json
import sys

print(json.dumps({
    "target_resolved": True,
    "canary_target": sys.argv[1],
    "target_source": sys.argv[2],
    "wrapper_status": sys.argv[3],
    "wrapper_state": sys.argv[4],
    "whatsapp_state": sys.argv[5],
    "provider_delivery_status": sys.argv[6],
    "provider_delivery_reason": sys.argv[7],
    "message_id": sys.argv[8],
    "wrapper_report": sys.argv[9],
}, ensure_ascii=True))
PY
)"

record_verify_task "$final_status" "$final_note" "$summary_json"

printf 'task_id: %s\n' "$TASK_ID"
printf 'target: %s\n' "$canary_target"
printf 'target_source: %s\n' "$target_source"
printf 'wrapper_status: %s\n' "$wrapper_status"
printf 'wrapper_state: %s\n' "$wrapper_state"
printf 'whatsapp_state: %s\n' "$whatsapp_state"
printf 'provider_delivery_status: %s\n' "$provider_delivery_status"
printf 'provider_delivery_reason: %s\n' "$provider_delivery_reason"
printf 'message_id: %s\n' "${message_id:-(none)}"
printf 'report_path: %s\n' "$REPORT_PATH"

case "$final_status" in
  PASS)
    printf 'VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_OK task=%s report=%s reason=provider_delivery_proved\n' "$TASK_ID" "$REPORT_PATH"
    exit 0
    ;;
  BLOCKED)
    printf 'VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_BLOCKED task=%s report=%s reason=%s\n' "$TASK_ID" "$REPORT_PATH" "${provider_delivery_status:-provider_proof_missing}"
    exit 2
    ;;
  *)
    printf 'VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_FAIL task=%s report=%s reason=canary_inconsistency\n' "$TASK_ID" "$REPORT_PATH" >&2
    exit 1
    ;;
esac
