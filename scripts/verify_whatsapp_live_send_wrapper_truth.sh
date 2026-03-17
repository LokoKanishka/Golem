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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-live-send-wrapper-truth.md"

PRESENT_TASK_ID=""
GATEWAY_TASK_ID=""
DRIFT_TASK_ID=""

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

record_case_report() {
  local case_name="$1"
  local task_id="$2"
  local status="$3"
  local note="$4"
  local summary_output="$5"

  append_report \
    "" \
    "## ${case_name}" \
    "- task_id: ${task_id}" \
    "- verify_status: ${status}" \
    "- note: ${note}" \
    "- task_delivery_summary:" \
    '```text' \
    "$summary_output" \
    '```'
}

advance_task_to_visible() {
  local task_id="$1"
  local prefix="$2"

  run_cmd "${prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-whatsapp-live-send-wrapper whatsapp 'task entered the outbound user-facing lane'"
  run_cmd "${prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-whatsapp-live-send-wrapper whatsapp 'technical acceptance happened before channel proof'"
  run_cmd "${prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-whatsapp-live-send-wrapper whatsapp 'the repo prepared the outbound WhatsApp lane locally'"
  run_cmd "${prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-whatsapp-live-send-wrapper whatsapp 'the repo now requires channel truth before a final user-facing claim'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Live Send Wrapper Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that the canonical repo-local WhatsApp live send wrapper is task-bound,
persists auditable evidence, updates delivery.whatsapp conservatively, and reclassifies the live
user journey smoke away from wrapper absence.
EOF
}

generate_header

printf '# WhatsApp Live Send Wrapper Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Wrapper Present Path / Create Task" "./scripts/task_new.sh verification-whatsapp-live-send-wrapper 'Verify WhatsApp wrapper dry-run path'"
PRESENT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Wrapper Present Path / Dry Run Wrapper" "./scripts/task_send_whatsapp_live.sh $PRESENT_TASK_ID +5491100000001 --message 'GOLEM-209 wrapper dry-run path' --dry-run --json"
present_wrapper_output="$LAST_OUTPUT"
present_wrapper_exit="$LAST_EXIT_CODE"
run_cmd "Wrapper Present Path / Delivery Summary" "./scripts/task_delivery_summary.sh $PRESENT_TASK_ID"
present_delivery_summary="$LAST_OUTPUT"
run_cmd "Wrapper Present Path / Task Summary" "./scripts/task_summary.sh $PRESENT_TASK_ID"
present_task_summary="$LAST_OUTPUT"

if [ "$present_wrapper_exit" -eq 0 ] && \
   printf '%s\n' "$present_wrapper_output" | rg -q '"wrapper_status": "DRY_RUN"' && \
   printf '%s\n' "$present_delivery_summary" | rg -q '^whatsapp_delivery_state: requested$' && \
   printf '%s\n' "$present_task_summary" | rg -q '^outputs: [1-9][0-9]*$' && \
   printf '%s\n' "$present_task_summary" | rg -q '^artifacts: [1-9][0-9]*$'; then
  present_status="PASS"
  present_note="wrapper dry-run proved that the repo now exposes a task-bound WhatsApp send path with persisted evidence"
else
  present_status="FAIL"
  present_note="wrapper dry-run did not leave the expected task-bound evidence or conservative requested state"
fi
record_case_report "Wrapper Present Path" "$PRESENT_TASK_ID" "$present_status" "$present_note" "$present_task_summary"

run_cmd "Gateway Acceptance Path / Create Task" "./scripts/task_new.sh verification-whatsapp-live-send-wrapper 'Verify WhatsApp wrapper gateway acceptance path'"
GATEWAY_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$GATEWAY_TASK_ID" "Gateway Acceptance Path"
run_cmd "Gateway Acceptance Path / Wrapper With Fixture" "GOLEM_WHATSAPP_SEND_FIXTURE_JSON='{\"channel\":\"whatsapp\",\"to\":\"+5491100000002\",\"messageId\":\"wamid.wrapper.gateway.001\",\"handledBy\":\"gateway\"}' ./scripts/task_send_whatsapp_live.sh $GATEWAY_TASK_ID +5491100000002 --message 'GOLEM-209 wrapper gateway path' --json"
gateway_wrapper_output="$LAST_OUTPUT"
gateway_wrapper_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Acceptance Path / Claim delivered" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-live-send-wrapper delivered 'attempted delivered wording with gateway acceptance only'"
gateway_delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Acceptance Path / Claim accepted_by_gateway" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-live-send-wrapper accepted_by_gateway 'claim kept at gateway acceptance wording'"
gateway_allowed_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Acceptance Path / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $GATEWAY_TASK_ID verify-whatsapp-live-send-wrapper whatsapp 'attempted generic final success with gateway acceptance only' 'final success claim'"
gateway_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Acceptance Path / Delivery Summary" "./scripts/task_delivery_summary.sh $GATEWAY_TASK_ID"
gateway_summary="$LAST_OUTPUT"

if [ "$gateway_wrapper_exit" -eq 0 ] && \
   printf '%s\n' "$gateway_wrapper_output" | rg -q '"wrapper_status": "ACCEPTED_BY_GATEWAY"' && \
   [ "$gateway_delivered_claim_exit" -eq 2 ] && \
   [ "$gateway_allowed_claim_exit" -eq 0 ] && \
   [ "$gateway_generic_claim_exit" -eq 2 ] && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_message_ids: wamid\.wrapper\.gateway\.001$'; then
  gateway_status="PASS"
  gateway_note="wrapper gateway acceptance path persisted message_id, updated delivery.whatsapp conservatively, and kept higher claims blocked"
else
  gateway_status="FAIL"
  gateway_note="wrapper gateway acceptance path did not persist the expected conservative WhatsApp truth"
fi
record_case_report "Gateway Acceptance Path" "$GATEWAY_TASK_ID" "$gateway_status" "$gateway_note" "$gateway_summary"

run_cmd "Drift Path / Create Task" "./scripts/task_new.sh verification-whatsapp-live-send-wrapper 'Verify WhatsApp wrapper drift path'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$DRIFT_TASK_ID" "Drift Path"
run_cmd "Drift Path / Wrapper With Base Fixture" "GOLEM_WHATSAPP_SEND_FIXTURE_JSON='{\"channel\":\"whatsapp\",\"to\":\"+5491100000003\",\"messageId\":\"wamid.wrapper.drift.base\",\"handledBy\":\"gateway\"}' ./scripts/task_send_whatsapp_live.sh $DRIFT_TASK_ID +5491100000003 --message 'GOLEM-209 drift base path' --json"
run_cmd "Drift Path / Wrapper With Mismatched Fixture" "GOLEM_WHATSAPP_SEND_FIXTURE_JSON='{\"channel\":\"whatsapp\",\"to\":\"+5491100000003\",\"messageId\":\"wamid.wrapper.drift.other\",\"handledBy\":\"gateway\"}' ./scripts/task_send_whatsapp_live.sh $DRIFT_TASK_ID +5491100000003 --message 'GOLEM-209 drift mismatch path' --json"
drift_wrapper_exit="$LAST_EXIT_CODE"
drift_wrapper_output="$LAST_OUTPUT"
run_cmd "Drift Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_wrapper_exit" -eq 1 ] && \
   printf '%s\n' "$drift_wrapper_output" | rg -q '"wrapper_status": "FAIL"' && \
   printf '%s\n' "$drift_wrapper_output" | rg -q '"message_id_drift_expected": "wamid.wrapper.drift.base"' && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_message_ids: wamid\.wrapper\.drift\.base$'; then
  drift_status="PASS"
  drift_note="wrapper drift detection failed loudly and preserved the original accepted_by_gateway evidence"
else
  drift_status="FAIL"
  drift_note="wrapper drift detection did not preserve or classify the tracked message_id coherently"
fi
record_case_report "Drift Path" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

run_cmd "Journey Recheck Hook / Live User Journey Smoke" "bash ./scripts/verify_live_user_journey_smoke.sh"
journey_output="$LAST_OUTPUT"
journey_exit="$LAST_EXIT_CODE"
journey_report="$(python3 - "$journey_output" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'^report_path: (\S+)$', text, re.MULTILINE)
if match:
    print(match.group(1))
    raise SystemExit(0)
match = re.search(r'^VERIFY_LIVE_USER_JOURNEY_SMOKE_(?:OK|BLOCKED|FAIL)\b.*\breport=(\S+)', text, re.MULTILINE)
print(match.group(1) if match else "")
PY
)"

if [ "$journey_exit" -eq 2 ] && \
   printf '%s\n' "$journey_output" | rg -q '^whatsapp delivery \| BLOCKED \|' && \
   printf '%s\n' "$journey_output" | rg -q 'live_send_path_verify=VERIFY_WHATSAPP_LIVE_SEND_PATH_OK' && \
   ! printf '%s\n' "$journey_output" | rg -q 'repo_canonical_whatsapp_live_send_wrapper_missing'; then
  journey_status="PASS"
  journey_note="Journey B now consumes the canonical wrapper/send-path truth and no longer blocks because the wrapper is missing"
else
  journey_status="FAIL"
  journey_note="Journey B did not reclassify coherently through the canonical wrapper/send-path truth"
fi
append_report \
  "" \
  "## Journey Recheck Hook" \
  "- verify_status: ${journey_status}" \
  "- note: ${journey_note}" \
  "- report_path: ${journey_report}" \
  "- smoke_output:" \
  '```text' \
  "$journey_output" \
  '```'

printf '\ncase | status | note | task_id\n'
printf 'wrapper present + task-bound | %s | %s | %s\n' "$present_status" "$present_note" "$PRESENT_TASK_ID"
printf 'gateway acceptance path | %s | %s | %s\n' "$gateway_status" "$gateway_note" "$GATEWAY_TASK_ID"
printf 'claim gating | %s | %s | %s\n' "$gateway_status" "$gateway_note" "$GATEWAY_TASK_ID"
printf 'drift / inconsistency | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'journey recheck hook | %s | %s | %s\n' "$journey_status" "$journey_note" "${journey_report:-"(smoke-report-missing)"}"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$present_status" = "PASS" ] && [ "$gateway_status" = "PASS" ] && [ "$drift_status" = "PASS" ] && [ "$journey_status" = "PASS" ]; then
  printf 'VERIFY_WHATSAPP_LIVE_SEND_WRAPPER_TRUTH_OK present=%s gateway=%s drift=%s journey_report=%s report=%s\n' \
    "$PRESENT_TASK_ID" "$GATEWAY_TASK_ID" "$DRIFT_TASK_ID" "$journey_report" "$REPORT_PATH"
  exit 0
fi

printf 'VERIFY_WHATSAPP_LIVE_SEND_WRAPPER_TRUTH_FAIL present=%s gateway=%s drift=%s journey_report=%s report=%s\n' \
  "$PRESENT_TASK_ID" "$GATEWAY_TASK_ID" "$DRIFT_TASK_ID" "$journey_report" "$REPORT_PATH" >&2
exit 1
