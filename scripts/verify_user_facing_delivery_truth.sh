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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-user-facing-delivery-truth.md"

PARTIAL_TASK_ID=""
VISIBLE_TASK_ID=""
VERIFIED_TASK_ID=""
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
    "- delivery_summary:" \
    '```text' \
    "$summary_output" \
    '```'
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# User-Facing Delivery Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that technical acceptance and user-facing delivery remain separate in the task model.
EOF
}

generate_header

printf '# User-Facing Delivery Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Partial Accepted Path / Create Task" "./scripts/task_new.sh verification-delivery 'Verify delivery partial accepted'"
PARTIAL_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Partial Accepted Path / Move Technical Lifecycle" "./scripts/task_update.sh $PARTIAL_TASK_ID running"
run_cmd "Partial Accepted Path / Technical Close" "./scripts/task_close.sh $PARTIAL_TASK_ID done 'technical acceptance closed before user visibility'"
run_cmd "Partial Accepted Path / submitted" "./scripts/task_record_delivery_transition.sh $PARTIAL_TASK_ID submitted verify-user-delivery repo-internal 'task submitted to delivery lane'"
run_cmd "Partial Accepted Path / accepted" "./scripts/task_record_delivery_transition.sh $PARTIAL_TASK_ID accepted verify-user-delivery repo-internal 'technical output accepted but not yet shown to the user'"
run_cmd "Partial Accepted Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $PARTIAL_TASK_ID verify-user-delivery terminal 'attempted final user-facing success claim before visible' 'final success claim'"
partial_claim_exit="$LAST_EXIT_CODE"
run_cmd "Partial Accepted Path / Delivery Summary" "./scripts/task_delivery_summary.sh $PARTIAL_TASK_ID"
partial_summary="$LAST_OUTPUT"

if [ "$partial_claim_exit" -eq 2 ] && printf '%s\n' "$partial_summary" | rg -q '^delivery_state: accepted$'; then
  partial_status="PASS"
  partial_note="task reached accepted only and the repo refused a user-facing success claim"
else
  partial_status="FAIL"
  partial_note="partial accepted path did not preserve the claim guardrail"
fi
record_case_report "Partial Accepted Path" "$PARTIAL_TASK_ID" "$partial_status" "$partial_note" "$partial_summary"

run_cmd "Visible Path / Create Task" "./scripts/task_new.sh verification-delivery 'Verify delivery visible path'"
VISIBLE_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Visible Path / submitted" "./scripts/task_record_delivery_transition.sh $VISIBLE_TASK_ID submitted verify-user-delivery repo-internal 'task submitted to outbound delivery flow'"
run_cmd "Visible Path / accepted" "./scripts/task_record_delivery_transition.sh $VISIBLE_TASK_ID accepted verify-user-delivery repo-internal 'technical acceptance recorded'"
run_cmd "Visible Path / delivered" "./scripts/task_record_delivery_transition.sh $VISIBLE_TASK_ID delivered verify-user-delivery whatsapp 'message queued into the user-facing outbound lane'"
run_cmd "Visible Path / visible" "./scripts/task_record_delivery_transition.sh $VISIBLE_TASK_ID visible verify-user-delivery whatsapp 'delivery evidence confirms the user can already see the message'"
run_cmd "Visible Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $VISIBLE_TASK_ID verify-user-delivery whatsapp 'final success claim after visible evidence exists' 'final success claim'"
visible_claim_exit="$LAST_EXIT_CODE"
run_cmd "Visible Path / Delivery Summary" "./scripts/task_delivery_summary.sh $VISIBLE_TASK_ID"
visible_summary="$LAST_OUTPUT"

if [ "$visible_claim_exit" -eq 0 ] && printf '%s\n' "$visible_summary" | rg -q '^delivery_state: visible$' && \
   printf '%s\n' "$visible_summary" | rg -q '^user_facing_ready: yes$'; then
  visible_status="PASS"
  visible_note="task reached visible with valid evidence and the user-facing success claim was allowed"
else
  visible_status="FAIL"
  visible_note="visible path did not preserve the visible threshold semantics"
fi
record_case_report "Visible Path" "$VISIBLE_TASK_ID" "$visible_status" "$visible_note" "$visible_summary"

run_cmd "Verified Path / Create Task" "./scripts/task_new.sh verification-delivery 'Verify delivery verified-by-user path'"
VERIFIED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Verified Path / submitted" "./scripts/task_record_delivery_transition.sh $VERIFIED_TASK_ID submitted verify-user-delivery repo-internal 'task submitted to outbound delivery flow'"
run_cmd "Verified Path / accepted" "./scripts/task_record_delivery_transition.sh $VERIFIED_TASK_ID accepted verify-user-delivery repo-internal 'technical acceptance recorded'"
run_cmd "Verified Path / delivered" "./scripts/task_record_delivery_transition.sh $VERIFIED_TASK_ID delivered verify-user-delivery email 'delivery sent through the selected user-facing channel'"
run_cmd "Verified Path / visible" "./scripts/task_record_delivery_transition.sh $VERIFIED_TASK_ID visible verify-user-delivery email 'mailbox evidence shows the output is visible to the user'"
run_cmd "Verified Path / verified_by_user" "./scripts/task_record_delivery_transition.sh $VERIFIED_TASK_ID verified_by_user user email 'user explicitly confirmed the delivery'"
run_cmd "Verified Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $VERIFIED_TASK_ID verify-user-delivery email 'final success claim after explicit user confirmation' 'final success claim'"
verified_claim_exit="$LAST_EXIT_CODE"
run_cmd "Verified Path / Delivery Summary" "./scripts/task_delivery_summary.sh $VERIFIED_TASK_ID"
verified_summary="$LAST_OUTPUT"

if [ "$verified_claim_exit" -eq 0 ] && printf '%s\n' "$verified_summary" | rg -q '^delivery_state: verified_by_user$'; then
  verified_status="PASS"
  verified_note="task reached explicit user confirmation and remained claimable as user-facing success"
else
  verified_status="FAIL"
  verified_note="verified_by_user path did not persist the final confirmation semantics"
fi
record_case_report "Verified By User Path" "$VERIFIED_TASK_ID" "$verified_status" "$verified_note" "$verified_summary"

run_cmd "Invalid Drift Path / Create Task" "./scripts/task_new.sh verification-delivery 'Verify delivery drift path'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Invalid Drift Path / Attempt accepted before submitted" "./scripts/task_record_delivery_transition.sh $DRIFT_TASK_ID accepted verify-user-delivery repo-internal 'invalid drift attempt without submitted'"
drift_exit="$LAST_EXIT_CODE"
run_cmd "Invalid Drift Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_exit" -ne 0 ] && printf '%s\n' "$drift_summary" | rg -q '^delivery_state: \(none\)$'; then
  drift_status="PASS"
  drift_note="invalid transition drift was rejected before corrupting the delivery state"
else
  drift_status="FAIL"
  drift_note="invalid transition drift was not blocked as expected"
fi
record_case_report "Invalid Drift Path" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

printf '\ncase | status | note | task_id\n'
printf 'partial accepted | %s | %s | %s\n' "$partial_status" "$partial_note" "$PARTIAL_TASK_ID"
printf 'visible | %s | %s | %s\n' "$visible_status" "$visible_note" "$VISIBLE_TASK_ID"
printf 'verified_by_user | %s | %s | %s\n' "$verified_status" "$verified_note" "$VERIFIED_TASK_ID"
printf 'invalid drift | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$partial_status" = "PASS" ] && [ "$visible_status" = "PASS" ] && [ "$verified_status" = "PASS" ] && [ "$drift_status" = "PASS" ]; then
  printf 'VERIFY_USER_FACING_DELIVERY_TRUTH_OK partial=%s visible=%s verified=%s drift=%s report=%s\n' \
    "$PARTIAL_TASK_ID" "$VISIBLE_TASK_ID" "$VERIFIED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
  exit 0
fi

printf 'VERIFY_USER_FACING_DELIVERY_TRUTH_FAIL partial=%s visible=%s verified=%s drift=%s report=%s\n' \
  "$PARTIAL_TASK_ID" "$VISIBLE_TASK_ID" "$VERIFIED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH" >&2
exit 1
