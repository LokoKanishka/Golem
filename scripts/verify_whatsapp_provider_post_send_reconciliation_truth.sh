#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
TIMESTAMP="$({ python3 - <<'PY'
import datetime
print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
PY
} )"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-provider-post-send-reconciliation-truth.md"
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

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for part in sys.argv[2].split('.'):
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

  ./scripts/task_add_artifact.sh "$TASK_ID" whatsapp-provider-post-send-reconciliation-truth-report "$report_rel" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$TASK_ID" whatsapp-provider-post-send-reconciliation-truth "$exit_code" "$final_note" >/dev/null

  case "$final_status" in
    PASS) ./scripts/task_close.sh "$TASK_ID" done "$final_note" >/dev/null ;;
    BLOCKED) ./scripts/task_close.sh "$TASK_ID" blocked "$final_note" >/dev/null ;;
    *) ./scripts/task_close.sh "$TASK_ID" failed "$final_note" >/dev/null ;;
  esac
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF2
# WhatsApp Provider Post-Send Reconciliation Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report answers one operational question:

After a real WhatsApp send was accepted by gateway, can the current runtime expose
strong provider proof through a repo-local canonical reconciliation lane?
EOF2
}

generate_header

printf '# WhatsApp Provider Post-Send Reconciliation Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Create Verify Task" "./scripts/task_new.sh verification-whatsapp-provider-post-send-reconciliation 'Verify WhatsApp post-send provider reconciliation truth'"
TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
if [ -z "$TASK_ID" ]; then
  printf 'VERIFY_WHATSAPP_PROVIDER_POST_SEND_RECONCILIATION_TRUTH_FAIL report=%s task=(missing) reason=task_creation_failed\n' "$REPORT_PATH" >&2
  exit 1
fi

run_cmd "Move Verify Task To Running" "./scripts/task_update.sh $TASK_ID running"
run_cmd "Run Live Provider Canary" "bash ./scripts/verify_whatsapp_live_provider_canary.sh"
canary_output="$LAST_OUTPUT"
canary_exit="$LAST_EXIT_CODE"
canary_report="$(extract_report_path "$canary_output")"
canary_marker="$(printf '%s\n' "$canary_output" | awk '/^VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_(OK|BLOCKED|FAIL) / {print $1}' | tail -n 1)"
source_task_id="$(printf '%s\n' "$canary_output" | awk '/^task_id: / {print $2}' | tail -n 1)"
source_message_id="$(printf '%s\n' "$canary_output" | awk '/^message_id: / {print $2}' | tail -n 1)"

if [ -z "$source_task_id" ]; then
  final_status="FAIL"
  final_note="the live canary did not return a task id, so post-send reconciliation could not be attempted coherently"
  summary_json="$(python3 - "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({"source_task_id": "", "reconciliation_status": "FAIL", "dominant_blocker": "canary_task_missing", "report_path": sys.argv[1]}, ensure_ascii=True))
PY
)"
  append_report "" "## Live Canary" "- canary_marker: ${canary_marker:-'(none)'}" "- canary_report: ${canary_report:-'(none)'}" "- note: ${final_note}"
  record_verify_task "$final_status" "$final_note" "$summary_json"
  printf 'report_path: %s\n' "$REPORT_PATH"
  printf 'VERIFY_WHATSAPP_PROVIDER_POST_SEND_RECONCILIATION_TRUTH_FAIL task=%s report=%s reason=canary_task_missing\n' "$TASK_ID" "$REPORT_PATH" >&2
  exit 1
fi

run_cmd "Run Post-Send Reconciliation" "./scripts/task_reconcile_whatsapp_provider_delivery.sh $source_task_id --actor verify-whatsapp-provider-post-send-reconciliation --json"
reconcile_output="$LAST_OUTPUT"
reconcile_exit="$LAST_EXIT_CODE"
reconciliation_status="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("reconciliation_status", ""))
except Exception:
    print("")
PY
)"
resolution="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("resolution", ""))
except Exception:
    print("")
PY
)"
dominant_blocker="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("dominant_blocker", ""))
except Exception:
    print("")
PY
)"
reconcile_report="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("report_path", ""))
except Exception:
    print("")
PY
)"
capabilities_surface="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("capabilities_surface", ""))
except Exception:
    print("")
PY
)"
message_read_surface="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("message_read_surface", ""))
except Exception:
    print("")
PY
)"
logs_surface="$(python3 - "$reconcile_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("logs_surface", ""))
except Exception:
    print("")
PY
)"

run_cmd "Claim Delivered Wording" "./scripts/task_claim_whatsapp_delivery.sh $source_task_id verify-whatsapp-provider-post-send-reconciliation delivered 'post-send reconciliation verifies whether delivered wording is now honestly authorized'"
delivered_claim_output="$LAST_OUTPUT"
delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Claim Generic Final Success" "./scripts/task_claim_user_facing_success.sh $source_task_id verify-whatsapp-provider-post-send-reconciliation whatsapp 'post-send reconciliation verifies whether generic final success is now honestly authorized' 'final success claim'"
generic_claim_output="$LAST_OUTPUT"
generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Delivery Summary" "./scripts/task_delivery_summary.sh $source_task_id"
delivery_summary="$LAST_OUTPUT"

whatsapp_state="$(task_field "$source_task_id" delivery.whatsapp.current_state)"
provider_delivery_status="$(task_field "$source_task_id" delivery.whatsapp.provider_delivery_status)"
provider_delivery_reason="$(task_field "$source_task_id" delivery.whatsapp.provider_delivery_reason)"

final_status="BLOCKED"
final_note="the repo exposed a canonical post-send reconciliation lane, but the current runtime still did not prove provider delivery strongly enough"
if [ "$canary_exit" -eq 1 ] || [ "$canary_marker" = "VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_FAIL" ]; then
  final_status="FAIL"
  final_note="the live provider canary failed internally before post-send reconciliation could be trusted"
elif [ "$reconcile_exit" -eq 1 ] || [ "$reconciliation_status" = "FAIL" ]; then
  final_status="FAIL"
  final_note="the canonical post-send reconciliation wrapper failed internally or returned incoherent evidence"
elif [ "$resolution" = "delivered" ] && { [ "$whatsapp_state" = "delivered" ] || [ "$whatsapp_state" = "verified_by_user" ]; }; then
  if [ "$delivered_claim_exit" -eq 0 ] && [ "$generic_claim_exit" -eq 0 ]; then
    final_status="PASS"
    final_note="the runtime exposed strong provider proof through the canonical post-send reconciliation lane"
  else
    final_status="FAIL"
    final_note="post-send reconciliation reached delivered-level truth, but the claim gates did not stay coherent"
  fi
elif [ "$reconcile_exit" -eq 2 ] && [ "$reconciliation_status" = "BLOCKED" ]; then
  if printf '%s\n' "$delivered_claim_output" | rg -q '^TASK_WHATSAPP_CLAIM_BLOCKED ' && printf '%s\n' "$generic_claim_output" | rg -q '^TASK_USER_FACING_CLAIM_BLOCKED '; then
    final_status="BLOCKED"
    final_note="the canonical post-send reconciliation lane proved the current observable ceiling honestly: WhatsApp read is unsupported and logs only expose outbound send evidence"
  else
    final_status="FAIL"
    final_note="post-send reconciliation stayed below delivered, but one of the claim gates inflated the outcome"
  fi
else
  final_status="FAIL"
  final_note="post-send reconciliation ended in an incoherent state that the verify could not classify honestly"
fi

append_report \
  "" \
  "## Live Canary" \
  "- canary_marker: ${canary_marker}" \
  "- canary_report: ${canary_report}" \
  "- source_task_id: ${source_task_id}" \
  "- source_message_id: ${source_message_id:-'(none)'}" \
  "" \
  "## Reconciliation Result" \
  "- reconciliation_status: ${reconciliation_status}" \
  "- resolution: ${resolution}" \
  "- dominant_blocker: ${dominant_blocker}" \
  "- capabilities_surface: ${capabilities_surface}" \
  "- message_read_surface: ${message_read_surface}" \
  "- logs_surface: ${logs_surface}" \
  "- reconcile_report: ${reconcile_report}" \
  "- whatsapp_state: ${whatsapp_state}" \
  "- provider_delivery_status: ${provider_delivery_status}" \
  "- provider_delivery_reason: ${provider_delivery_reason}" \
  "- delivery_summary:" \
  '```text' \
  "$delivery_summary" \
  '```'

summary_json="$(python3 - "$source_task_id" "$source_message_id" "$reconciliation_status" "$resolution" "$dominant_blocker" "$capabilities_surface" "$message_read_surface" "$logs_surface" "$whatsapp_state" "$provider_delivery_status" "$provider_delivery_reason" "$canary_marker" "$canary_report" "$reconcile_report" "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "source_task_id": sys.argv[1],
    "source_message_id": sys.argv[2],
    "reconciliation_status": sys.argv[3],
    "resolution": sys.argv[4],
    "dominant_blocker": sys.argv[5],
    "capabilities_surface": sys.argv[6],
    "message_read_surface": sys.argv[7],
    "logs_surface": sys.argv[8],
    "whatsapp_state": sys.argv[9],
    "provider_delivery_status": sys.argv[10],
    "provider_delivery_reason": sys.argv[11],
    "canary_marker": sys.argv[12],
    "canary_report": sys.argv[13],
    "reconcile_report": sys.argv[14],
    "report_path": sys.argv[15],
}, ensure_ascii=True))
PY
)"
record_verify_task "$final_status" "$final_note" "$summary_json"

printf 'task_id: %s\n' "$source_task_id"
printf 'message_id: %s\n' "${source_message_id:-(none)}"
printf 'canary_verify: %s\n' "$canary_marker"
printf 'reconciliation_status: %s\n' "$reconciliation_status"
printf 'resolution: %s\n' "$resolution"
printf 'dominant_blocker: %s\n' "$dominant_blocker"
printf 'capabilities_surface: %s\n' "$capabilities_surface"
printf 'message_read_surface: %s\n' "$message_read_surface"
printf 'logs_surface: %s\n' "$logs_surface"
printf 'whatsapp_state: %s\n' "$whatsapp_state"
printf 'provider_delivery_status: %s\n' "$provider_delivery_status"
printf 'provider_delivery_reason: %s\n' "$provider_delivery_reason"
printf 'report_path: %s\n' "$REPORT_PATH"

case "$final_status" in
  PASS)
    printf 'VERIFY_WHATSAPP_PROVIDER_POST_SEND_RECONCILIATION_TRUTH_OK task=%s report=%s reason=provider_delivery_proved\n' "$source_task_id" "$REPORT_PATH"
    exit 0
    ;;
  BLOCKED)
    printf 'VERIFY_WHATSAPP_PROVIDER_POST_SEND_RECONCILIATION_TRUTH_BLOCKED task=%s report=%s reason=%s\n' "$source_task_id" "$REPORT_PATH" "${dominant_blocker:-provider_post_send_surface_missing}"
    exit 2
    ;;
  *)
    printf 'VERIFY_WHATSAPP_PROVIDER_POST_SEND_RECONCILIATION_TRUTH_FAIL task=%s report=%s reason=reconciliation_inconsistency\n' "$source_task_id" "$REPORT_PATH" >&2
    exit 1
    ;;
esac
