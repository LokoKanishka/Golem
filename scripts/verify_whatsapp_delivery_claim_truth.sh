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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-delivery-claim-truth.md"

GATEWAY_TASK_ID=""
DELIVERED_TASK_ID=""
VERIFIED_TASK_ID=""
AMBIGUOUS_TASK_ID=""
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

advance_task_to_visible() {
  local task_id="$1"
  local prefix="$2"

  run_cmd "${prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-whatsapp-delivery repo-internal 'task entered the outbound user-facing lane'"
  run_cmd "${prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-whatsapp-delivery repo-internal 'technical output accepted before channel delivery truth'"
  run_cmd "${prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-whatsapp-delivery whatsapp 'the message entered the outbound WhatsApp lane'"
  run_cmd "${prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-whatsapp-delivery whatsapp 'user-facing truth now depends on channel-specific WhatsApp evidence'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Delivery Claim Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that WhatsApp wording degrades to the exact delivery evidence instead of inflating technical gateway acceptance into delivery.
EOF
}

generate_header

printf '# WhatsApp Delivery Claim Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Gateway Accepted Path / Create Task" "./scripts/task_new.sh verification-whatsapp-delivery 'Verify WhatsApp accepted-by-gateway path'"
GATEWAY_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Gateway Accepted Path / Move Technical Lifecycle" "./scripts/task_update.sh $GATEWAY_TASK_ID running"
run_cmd "Gateway Accepted Path / Technical Close" "./scripts/task_close.sh $GATEWAY_TASK_ID done 'technical send request closed before WhatsApp delivery truth'"
advance_task_to_visible "$GATEWAY_TASK_ID" "Gateway Accepted Path"
run_cmd "Gateway Accepted Path / requested" "./scripts/task_record_whatsapp_delivery.sh $GATEWAY_TASK_ID requested verify-whatsapp-delivery fixture-gateway +5491100000001 - 'local send request captured before gateway acceptance' --run-id run-gateway-only"
run_cmd "Gateway Accepted Path / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $GATEWAY_TASK_ID accepted_by_gateway verify-whatsapp-delivery fixture-gateway +5491100000001 wamid.gateway.accepted 'gateway accepted the request and returned a message id' --run-id run-gateway-only"
run_cmd "Gateway Accepted Path / Claim Delivered" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-delivery delivered 'attempted to claim delivered with gateway-only evidence'"
gateway_delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Accepted Path / Claim Accepted By Gateway" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-delivery accepted_by_gateway 'claim degraded to gateway acceptance wording'"
gateway_allowed_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Accepted Path / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $GATEWAY_TASK_ID verify-whatsapp-delivery whatsapp 'attempted generic final success even though WhatsApp is only gateway-accepted' 'final success claim'"
gateway_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Accepted Path / Delivery Summary" "./scripts/task_delivery_summary.sh $GATEWAY_TASK_ID"
gateway_summary="$LAST_OUTPUT"

if [ "$gateway_delivered_claim_exit" -eq 2 ] && [ "$gateway_allowed_claim_exit" -eq 0 ] && [ "$gateway_generic_claim_exit" -eq 2 ] && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_allowed_user_facing_claim: aceptado por gateway$'; then
  gateway_status="PASS"
  gateway_note="gateway-only evidence stayed at accepted_by_gateway, rejected delivered wording, and blocked generic final success"
else
  gateway_status="FAIL"
  gateway_note="gateway-only WhatsApp evidence was inflated or summarized dishonestly"
fi
record_case_report "Gateway Accepted Path" "$GATEWAY_TASK_ID" "$gateway_status" "$gateway_note" "$gateway_summary"

run_cmd "Delivered Path / Create Task" "./scripts/task_new.sh verification-whatsapp-delivery 'Verify WhatsApp delivered path'"
DELIVERED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Delivered Path / Move Technical Lifecycle" "./scripts/task_update.sh $DELIVERED_TASK_ID running"
run_cmd "Delivered Path / Technical Close" "./scripts/task_close.sh $DELIVERED_TASK_ID done 'technical send request closed before WhatsApp delivery confirmation'"
advance_task_to_visible "$DELIVERED_TASK_ID" "Delivered Path"
run_cmd "Delivered Path / requested" "./scripts/task_record_whatsapp_delivery.sh $DELIVERED_TASK_ID requested verify-whatsapp-delivery fixture-gateway +5491100000002 - 'local send request captured before gateway acceptance' --run-id run-delivered"
run_cmd "Delivered Path / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $DELIVERED_TASK_ID accepted_by_gateway verify-whatsapp-delivery fixture-gateway +5491100000002 wamid.delivered.001 'gateway accepted and returned the message id' --run-id run-delivered"
run_cmd "Delivered Path / delivered" "./scripts/task_record_whatsapp_delivery.sh $DELIVERED_TASK_ID delivered verify-whatsapp-delivery fixture-provider +5491100000002 wamid.delivered.001 'provider delivery receipt confirms the message reached the channel' --run-id run-delivered --confidence high"
run_cmd "Delivered Path / Claim Delivered" "./scripts/task_claim_whatsapp_delivery.sh $DELIVERED_TASK_ID verify-whatsapp-delivery delivered 'delivery receipt exists and should authorize delivered wording'"
delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Delivered Path / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $DELIVERED_TASK_ID verify-whatsapp-delivery whatsapp 'generic final success after delivered WhatsApp evidence' 'final success claim'"
delivered_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Delivered Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DELIVERED_TASK_ID"
delivered_summary="$LAST_OUTPUT"

if [ "$delivered_claim_exit" -eq 0 ] && [ "$delivered_generic_claim_exit" -eq 0 ] && \
   printf '%s\n' "$delivered_summary" | rg -q '^whatsapp_delivery_state: delivered$' && \
   printf '%s\n' "$delivered_summary" | rg -q '^whatsapp_allowed_user_facing_claim: entregado$'; then
  delivered_status="PASS"
  delivered_note="delivered evidence authorized delivered wording and the generic final claim"
else
  delivered_status="FAIL"
  delivered_note="delivered WhatsApp evidence did not authorize the expected claim level"
fi
record_case_report "Delivered Path" "$DELIVERED_TASK_ID" "$delivered_status" "$delivered_note" "$delivered_summary"

run_cmd "Verified Path / Create Task" "./scripts/task_new.sh verification-whatsapp-delivery 'Verify WhatsApp verified-by-user path'"
VERIFIED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$VERIFIED_TASK_ID" "Verified Path"
run_cmd "Verified Path / requested" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID requested verify-whatsapp-delivery fixture-gateway +5491100000003 - 'local send request captured before gateway acceptance' --run-id run-verified"
run_cmd "Verified Path / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID accepted_by_gateway verify-whatsapp-delivery fixture-gateway +5491100000003 wamid.verified.001 'gateway accepted and returned the message id' --run-id run-verified"
run_cmd "Verified Path / delivered" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID delivered verify-whatsapp-delivery fixture-provider +5491100000003 wamid.verified.001 'delivery receipt confirms the message reached the channel' --run-id run-verified --confidence high"
run_cmd "Verified Path / verified_by_user" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID verified_by_user verify-whatsapp-delivery fixture-provider +5491100000003 wamid.verified.001 'the user explicitly confirmed the WhatsApp delivery' --run-id run-verified --confidence confirmed"
run_cmd "Verified Path / Claim Verified By User" "./scripts/task_claim_whatsapp_delivery.sh $VERIFIED_TASK_ID verify-whatsapp-delivery verified_by_user 'the user confirmation should authorize the highest claim level'"
verified_claim_exit="$LAST_EXIT_CODE"
run_cmd "Verified Path / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $VERIFIED_TASK_ID verify-whatsapp-delivery whatsapp 'generic final success after explicit user confirmation' 'final success claim'"
verified_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Verified Path / Delivery Summary" "./scripts/task_delivery_summary.sh $VERIFIED_TASK_ID"
verified_summary="$LAST_OUTPUT"

if [ "$verified_claim_exit" -eq 0 ] && [ "$verified_generic_claim_exit" -eq 0 ] && \
   printf '%s\n' "$verified_summary" | rg -q '^whatsapp_delivery_state: verified_by_user$' && \
   printf '%s\n' "$verified_summary" | rg -q '^whatsapp_allowed_user_facing_claim: confirmado por usuario$'; then
  verified_status="PASS"
  verified_note="explicit user confirmation persisted the highest WhatsApp claim level"
else
  verified_status="FAIL"
  verified_note="verified_by_user semantics did not persist coherently for WhatsApp"
fi
record_case_report "Verified By User Path" "$VERIFIED_TASK_ID" "$verified_status" "$verified_note" "$verified_summary"

run_cmd "Ambiguous Provider Path / Create Task" "./scripts/task_new.sh verification-whatsapp-delivery 'Verify WhatsApp ambiguous provider path'"
AMBIGUOUS_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$AMBIGUOUS_TASK_ID" "Ambiguous Provider Path"
run_cmd "Ambiguous Provider Path / requested" "./scripts/task_record_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID requested verify-whatsapp-delivery fixture-gateway +5491100000004 - 'local send request captured before gateway acceptance' --run-id run-ambiguous --confidence low"
run_cmd "Ambiguous Provider Path / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID accepted_by_gateway verify-whatsapp-delivery fixture-gateway +5491100000004 wamid.ambiguous.001 'gateway returned a message id but provider status is still pending/ambiguous' --run-id run-ambiguous --confidence low"
run_cmd "Ambiguous Provider Path / Claim Accepted By Provider" "./scripts/task_claim_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID verify-whatsapp-delivery accepted_by_provider 'attempted provider-level claim with ambiguous evidence'"
ambiguous_provider_claim_exit="$LAST_EXIT_CODE"
run_cmd "Ambiguous Provider Path / Claim Accepted By Gateway" "./scripts/task_claim_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID verify-whatsapp-delivery accepted_by_gateway 'claim kept at conservative gateway-accepted wording'"
ambiguous_gateway_claim_exit="$LAST_EXIT_CODE"
run_cmd "Ambiguous Provider Path / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $AMBIGUOUS_TASK_ID verify-whatsapp-delivery whatsapp 'generic final success attempted with ambiguous provider evidence' 'final success claim'"
ambiguous_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Ambiguous Provider Path / Delivery Summary" "./scripts/task_delivery_summary.sh $AMBIGUOUS_TASK_ID"
ambiguous_summary="$LAST_OUTPUT"

if [ "$ambiguous_provider_claim_exit" -eq 2 ] && [ "$ambiguous_gateway_claim_exit" -eq 0 ] && [ "$ambiguous_generic_claim_exit" -eq 2 ] && \
   printf '%s\n' "$ambiguous_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$ambiguous_summary" | rg -q '^whatsapp_delivery_confidence: low$'; then
  ambiguous_status="PASS"
  ambiguous_note="ambiguous provider evidence stayed conservative and did not inflate beyond gateway acceptance"
else
  ambiguous_status="FAIL"
  ambiguous_note="ambiguous provider evidence was not degraded conservatively"
fi
record_case_report "Ambiguous Provider Path" "$AMBIGUOUS_TASK_ID" "$ambiguous_status" "$ambiguous_note" "$ambiguous_summary"

run_cmd "Drift Path / Create Task" "./scripts/task_new.sh verification-whatsapp-delivery 'Verify WhatsApp drift path'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Drift Path / requested" "./scripts/task_record_whatsapp_delivery.sh $DRIFT_TASK_ID requested verify-whatsapp-delivery fixture-gateway +5491100000005 - 'local send request captured before gateway acceptance' --run-id run-drift"
run_cmd "Drift Path / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $DRIFT_TASK_ID accepted_by_gateway verify-whatsapp-delivery fixture-gateway +5491100000005 wamid.drift.base 'gateway accepted and returned the original message id' --run-id run-drift"
run_cmd "Drift Path / delivered with mismatched message_id" "./scripts/task_record_whatsapp_delivery.sh $DRIFT_TASK_ID delivered verify-whatsapp-delivery fixture-provider +5491100000005 wamid.drift.other 'provider receipt refers to a different message id and should be rejected' --run-id run-drift"
drift_record_exit="$LAST_EXIT_CODE"
run_cmd "Drift Path / Claim Delivered" "./scripts/task_claim_whatsapp_delivery.sh $DRIFT_TASK_ID verify-whatsapp-delivery delivered 'attempted delivered wording after message-id drift'"
drift_claim_exit="$LAST_EXIT_CODE"
run_cmd "Drift Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_record_exit" -ne 0 ] && [ "$drift_claim_exit" -eq 2 ] && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_message_ids: wamid\.drift\.base$'; then
  drift_status="PASS"
  drift_note="message-id drift was rejected explicitly and the persisted WhatsApp state remained conservative"
else
  drift_status="FAIL"
  drift_note="WhatsApp drift or inconsistency was not detected as expected"
fi
record_case_report "Drift Detection Path" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

printf '\ncase | status | note | task_id\n'
printf 'accepted_by_gateway only | %s | %s | %s\n' "$gateway_status" "$gateway_note" "$GATEWAY_TASK_ID"
printf 'delivered | %s | %s | %s\n' "$delivered_status" "$delivered_note" "$DELIVERED_TASK_ID"
printf 'verified_by_user | %s | %s | %s\n' "$verified_status" "$verified_note" "$VERIFIED_TASK_ID"
printf 'ambiguous provider result | %s | %s | %s\n' "$ambiguous_status" "$ambiguous_note" "$AMBIGUOUS_TASK_ID"
printf 'drift / inconsistency | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$gateway_status" = "PASS" ] && [ "$delivered_status" = "PASS" ] && [ "$verified_status" = "PASS" ] && [ "$ambiguous_status" = "PASS" ] && [ "$drift_status" = "PASS" ]; then
  printf 'VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_OK gateway=%s delivered=%s verified=%s ambiguous=%s drift=%s report=%s\n' \
    "$GATEWAY_TASK_ID" "$DELIVERED_TASK_ID" "$VERIFIED_TASK_ID" "$AMBIGUOUS_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
  exit 0
fi

printf 'VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_FAIL gateway=%s delivered=%s verified=%s ambiguous=%s drift=%s report=%s\n' \
  "$GATEWAY_TASK_ID" "$DELIVERED_TASK_ID" "$VERIFIED_TASK_ID" "$AMBIGUOUS_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH" >&2
exit 1
