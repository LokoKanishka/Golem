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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-provider-delivery-truth.md"

GATEWAY_TASK_ID=""
AMBIGUOUS_TASK_ID=""
DELIVERED_TASK_ID=""
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

advance_task_to_visible() {
  local task_id="$1"
  local prefix="$2"

  run_cmd "${prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-whatsapp-provider-delivery repo-internal 'task entered the outbound user-facing lane'"
  run_cmd "${prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-whatsapp-provider-delivery repo-internal 'technical output accepted before channel delivery truth'"
  run_cmd "${prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-whatsapp-provider-delivery whatsapp 'the message entered the outbound WhatsApp lane locally'"
  run_cmd "${prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-whatsapp-provider-delivery whatsapp 'user-facing truth now depends on provider delivery proof'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Provider Delivery Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that WhatsApp provider delivery proof stays task-bound, auditable,
conservative, and clearly separated from gateway acceptance.
EOF
}

generate_header

printf '# WhatsApp Provider Delivery Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Gateway Only / Create Task" "./scripts/task_new.sh verification-whatsapp-provider-delivery 'Verify WhatsApp gateway-only provider truth'"
GATEWAY_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$GATEWAY_TASK_ID" "Gateway Only"
run_cmd "Gateway Only / requested" "./scripts/task_record_whatsapp_delivery.sh $GATEWAY_TASK_ID requested verify-whatsapp-provider-delivery fixture-gateway +5491100000011 - 'local send request captured before gateway acceptance' --run-id run-gateway-only"
run_cmd "Gateway Only / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $GATEWAY_TASK_ID accepted_by_gateway verify-whatsapp-provider-delivery fixture-gateway +5491100000011 wamid.gateway.only.001 'gateway accepted the outbound request and returned a message id' --run-id run-gateway-only"
run_cmd "Gateway Only / Claim provider_delivery_unproved" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-provider-delivery provider_delivery_unproved 'attempted provider-unproved wording without any provider evidence'"
gateway_unproved_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Only / Claim accepted_by_gateway" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-provider-delivery accepted_by_gateway 'gateway wording stays allowed when no provider evidence exists'"
gateway_allowed_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Only / Claim delivered" "./scripts/task_claim_whatsapp_delivery.sh $GATEWAY_TASK_ID verify-whatsapp-provider-delivery delivered 'attempted delivered wording with gateway-only evidence'"
gateway_delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Only / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $GATEWAY_TASK_ID verify-whatsapp-provider-delivery whatsapp 'attempted generic final success with only gateway acceptance' 'final success claim'"
gateway_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Gateway Only / Delivery Summary" "./scripts/task_delivery_summary.sh $GATEWAY_TASK_ID"
gateway_summary="$LAST_OUTPUT"

if [ "$gateway_unproved_claim_exit" -eq 2 ] && [ "$gateway_allowed_claim_exit" -eq 0 ] && [ "$gateway_delivered_claim_exit" -eq 2 ] && [ "$gateway_generic_claim_exit" -eq 2 ] && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$gateway_summary" | rg -q '^whatsapp_provider_delivery_status: gateway_accepted$'; then
  gateway_status="PASS"
  gateway_note="gateway-only evidence stayed at accepted_by_gateway, blocked provider and delivered inflation, and kept generic final success blocked"
else
  gateway_status="FAIL"
  gateway_note="gateway-only evidence did not stay conservative under the provider truth model"
fi
record_case_report "Gateway Only" "$GATEWAY_TASK_ID" "$gateway_status" "$gateway_note" "$gateway_summary"

run_cmd "Provider Ambiguous / Create Task" "./scripts/task_new.sh verification-whatsapp-provider-delivery 'Verify WhatsApp provider ambiguous truth'"
AMBIGUOUS_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$AMBIGUOUS_TASK_ID" "Provider Ambiguous"
run_cmd "Provider Ambiguous / requested" "./scripts/task_record_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID requested verify-whatsapp-provider-delivery fixture-gateway +5491100000012 - 'local send request captured before gateway acceptance' --run-id run-ambiguous"
run_cmd "Provider Ambiguous / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID accepted_by_gateway verify-whatsapp-provider-delivery fixture-gateway +5491100000012 wamid.provider.ambiguous.001 'gateway accepted and returned the message id' --run-id run-ambiguous"
run_cmd "Provider Ambiguous / ambiguous proof" "./scripts/task_record_whatsapp_provider_delivery.sh $AMBIGUOUS_TASK_ID verify-whatsapp-provider-delivery fixture-provider +5491100000012 wamid.provider.ambiguous.001 ambiguous 'provider returned a pending/queued status that does not prove delivery' --run-id run-ambiguous --provider-status provider_pending --reason 'provider evidence is present but remains ambiguous for actual delivery' --normalized-evidence-json '{\"provider_status\":\"pending\",\"delivered\":false,\"proof_strength\":\"ambiguous\"}'"
ambiguous_record_exit="$LAST_EXIT_CODE"
run_cmd "Provider Ambiguous / Claim provider_delivery_unproved" "./scripts/task_claim_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID verify-whatsapp-provider-delivery provider_delivery_unproved 'provider ambiguity should authorize only the conservative provider-unproved wording'"
ambiguous_unproved_claim_exit="$LAST_EXIT_CODE"
run_cmd "Provider Ambiguous / Claim delivered" "./scripts/task_claim_whatsapp_delivery.sh $AMBIGUOUS_TASK_ID verify-whatsapp-provider-delivery delivered 'attempted delivered wording with ambiguous provider evidence'"
ambiguous_delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Provider Ambiguous / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $AMBIGUOUS_TASK_ID verify-whatsapp-provider-delivery whatsapp 'generic final success attempted with ambiguous provider evidence' 'final success claim'"
ambiguous_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Provider Ambiguous / Delivery Summary" "./scripts/task_delivery_summary.sh $AMBIGUOUS_TASK_ID"
ambiguous_summary="$LAST_OUTPUT"

if [ "$ambiguous_record_exit" -eq 0 ] && [ "$ambiguous_unproved_claim_exit" -eq 0 ] && [ "$ambiguous_delivered_claim_exit" -eq 2 ] && [ "$ambiguous_generic_claim_exit" -eq 2 ] && \
   printf '%s\n' "$ambiguous_summary" | rg -q '^whatsapp_delivery_state: provider_delivery_unproved$' && \
   printf '%s\n' "$ambiguous_summary" | rg -q '^whatsapp_provider_delivery_status: provider_pending$'; then
  ambiguous_status="PASS"
  ambiguous_note="ambiguous provider evidence persisted as provider_delivery_unproved, kept delivered wording blocked, and left the generic claim blocked"
else
  ambiguous_status="FAIL"
  ambiguous_note="ambiguous provider evidence was not classified conservatively"
fi
record_case_report "Provider Ambiguous" "$AMBIGUOUS_TASK_ID" "$ambiguous_status" "$ambiguous_note" "$ambiguous_summary"

run_cmd "Provider Delivered / Create Task" "./scripts/task_new.sh verification-whatsapp-provider-delivery 'Verify WhatsApp provider delivered truth'"
DELIVERED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$DELIVERED_TASK_ID" "Provider Delivered"
run_cmd "Provider Delivered / requested" "./scripts/task_record_whatsapp_delivery.sh $DELIVERED_TASK_ID requested verify-whatsapp-provider-delivery fixture-gateway +5491100000013 - 'local send request captured before gateway acceptance' --run-id run-delivered"
run_cmd "Provider Delivered / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $DELIVERED_TASK_ID accepted_by_gateway verify-whatsapp-provider-delivery fixture-gateway +5491100000013 wamid.provider.delivered.001 'gateway accepted and returned the message id' --run-id run-delivered"
run_cmd "Provider Delivered / delivered proof" "./scripts/task_record_whatsapp_provider_delivery.sh $DELIVERED_TASK_ID verify-whatsapp-provider-delivery fixture-provider +5491100000013 wamid.provider.delivered.001 delivered 'provider receipt confirms the message reached the destination channel' --run-id run-delivered --provider-status provider_delivered --reason 'provider receipt proves that the message reached the destination channel' --normalized-evidence-json '{\"provider_status\":\"delivered\",\"delivered\":true,\"proof_strength\":\"strong\"}'"
delivered_record_exit="$LAST_EXIT_CODE"
run_cmd "Provider Delivered / Claim delivered" "./scripts/task_claim_whatsapp_delivery.sh $DELIVERED_TASK_ID verify-whatsapp-provider-delivery delivered 'provider delivery proof should authorize delivered wording'"
delivered_claim_exit="$LAST_EXIT_CODE"
run_cmd "Provider Delivered / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $DELIVERED_TASK_ID verify-whatsapp-provider-delivery whatsapp 'generic final success after strong provider delivery proof' 'final success claim'"
delivered_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "Provider Delivered / Delivery Summary" "./scripts/task_delivery_summary.sh $DELIVERED_TASK_ID"
delivered_summary="$LAST_OUTPUT"

if [ "$delivered_record_exit" -eq 0 ] && [ "$delivered_claim_exit" -eq 0 ] && [ "$delivered_generic_claim_exit" -eq 0 ] && \
   printf '%s\n' "$delivered_summary" | rg -q '^whatsapp_delivery_state: delivered$' && \
   printf '%s\n' "$delivered_summary" | rg -q '^whatsapp_provider_delivery_status: provider_delivered$'; then
  delivered_status="PASS"
  delivered_note="strong provider proof authorized delivered wording and the generic final user-facing claim"
else
  delivered_status="FAIL"
  delivered_note="strong provider proof did not authorize the expected delivered semantics"
fi
record_case_report "Provider Delivered" "$DELIVERED_TASK_ID" "$delivered_status" "$delivered_note" "$delivered_summary"

run_cmd "User Confirmed / Create Task" "./scripts/task_new.sh verification-whatsapp-provider-delivery 'Verify WhatsApp explicit user confirmation truth'"
VERIFIED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$VERIFIED_TASK_ID" "User Confirmed"
run_cmd "User Confirmed / requested" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID requested verify-whatsapp-provider-delivery fixture-gateway +5491100000014 - 'local send request captured before gateway acceptance' --run-id run-verified"
run_cmd "User Confirmed / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $VERIFIED_TASK_ID accepted_by_gateway verify-whatsapp-provider-delivery fixture-gateway +5491100000014 wamid.provider.verified.001 'gateway accepted and returned the message id' --run-id run-verified"
run_cmd "User Confirmed / delivered proof" "./scripts/task_record_whatsapp_provider_delivery.sh $VERIFIED_TASK_ID verify-whatsapp-provider-delivery fixture-provider +5491100000014 wamid.provider.verified.001 delivered 'provider receipt confirms the message reached the destination channel' --run-id run-verified --provider-status provider_delivered --normalized-evidence-json '{\"provider_status\":\"delivered\",\"delivered\":true,\"proof_strength\":\"strong\"}'"
run_cmd "User Confirmed / explicit confirmation" "./scripts/task_record_whatsapp_provider_delivery.sh $VERIFIED_TASK_ID verify-whatsapp-provider-delivery fixture-provider +5491100000014 wamid.provider.verified.001 verified_by_user 'the user explicitly confirmed the WhatsApp delivery outcome' --run-id run-verified --normalized-evidence-json '{\"user_confirmed\":true,\"proof_strength\":\"confirmed\"}'"
verified_record_exit="$LAST_EXIT_CODE"
run_cmd "User Confirmed / Claim verified_by_user" "./scripts/task_claim_whatsapp_delivery.sh $VERIFIED_TASK_ID verify-whatsapp-provider-delivery verified_by_user 'explicit user confirmation should authorize the highest claim level'"
verified_claim_exit="$LAST_EXIT_CODE"
run_cmd "User Confirmed / Generic Final Claim" "./scripts/task_claim_user_facing_success.sh $VERIFIED_TASK_ID verify-whatsapp-provider-delivery whatsapp 'generic final success after explicit user confirmation' 'final success claim'"
verified_generic_claim_exit="$LAST_EXIT_CODE"
run_cmd "User Confirmed / Delivery Summary" "./scripts/task_delivery_summary.sh $VERIFIED_TASK_ID"
verified_summary="$LAST_OUTPUT"

if [ "$verified_record_exit" -eq 0 ] && [ "$verified_claim_exit" -eq 0 ] && [ "$verified_generic_claim_exit" -eq 0 ] && \
   printf '%s\n' "$verified_summary" | rg -q '^whatsapp_delivery_state: verified_by_user$' && \
   printf '%s\n' "$verified_summary" | rg -q '^whatsapp_provider_delivery_status: verified_by_user$'; then
  verified_status="PASS"
  verified_note="explicit user confirmation raised the task-bound WhatsApp truth to verified_by_user"
else
  verified_status="FAIL"
  verified_note="explicit user confirmation did not persist coherently"
fi
record_case_report "User Confirmed" "$VERIFIED_TASK_ID" "$verified_status" "$verified_note" "$verified_summary"

run_cmd "Drift / Create Task" "./scripts/task_new.sh verification-whatsapp-provider-delivery 'Verify WhatsApp provider drift detection'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$DRIFT_TASK_ID" "Drift"
run_cmd "Drift / requested" "./scripts/task_record_whatsapp_delivery.sh $DRIFT_TASK_ID requested verify-whatsapp-provider-delivery fixture-gateway +5491100000015 - 'local send request captured before gateway acceptance' --run-id run-drift"
run_cmd "Drift / accepted_by_gateway" "./scripts/task_record_whatsapp_delivery.sh $DRIFT_TASK_ID accepted_by_gateway verify-whatsapp-provider-delivery fixture-gateway +5491100000015 wamid.provider.drift.base 'gateway accepted and returned the original message id' --run-id run-drift"
run_cmd "Drift / delivered proof with wrong message_id" "./scripts/task_record_whatsapp_provider_delivery.sh $DRIFT_TASK_ID verify-whatsapp-provider-delivery fixture-provider +5491100000015 wamid.provider.drift.other delivered 'provider proof refers to a different message id and must be rejected' --run-id run-drift --provider-status provider_delivered --normalized-evidence-json '{\"provider_status\":\"delivered\",\"delivered\":true,\"proof_strength\":\"strong\"}'"
drift_record_exit="$LAST_EXIT_CODE"
run_cmd "Drift / Claim delivered" "./scripts/task_claim_whatsapp_delivery.sh $DRIFT_TASK_ID verify-whatsapp-provider-delivery delivered 'attempted delivered wording after provider message-id drift'"
drift_claim_exit="$LAST_EXIT_CODE"
run_cmd "Drift / Delivery Summary" "./scripts/task_delivery_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_record_exit" -ne 0 ] && [ "$drift_claim_exit" -eq 2 ] && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_delivery_state: accepted_by_gateway$' && \
   printf '%s\n' "$drift_summary" | rg -q '^whatsapp_message_ids: wamid\.provider\.drift\.base$'; then
  drift_status="PASS"
  drift_note="provider drift was rejected explicitly and the task stayed at the pre-proof conservative state"
else
  drift_status="FAIL"
  drift_note="provider drift or incompatible evidence was not detected correctly"
fi
record_case_report "Drift" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

printf '\ncase | status | note | task_id\n'
printf 'gateway only | %s | %s | %s\n' "$gateway_status" "$gateway_note" "$GATEWAY_TASK_ID"
printf 'provider ambiguous | %s | %s | %s\n' "$ambiguous_status" "$ambiguous_note" "$AMBIGUOUS_TASK_ID"
printf 'provider delivered proof | %s | %s | %s\n' "$delivered_status" "$delivered_note" "$DELIVERED_TASK_ID"
printf 'explicit user confirmation | %s | %s | %s\n' "$verified_status" "$verified_note" "$VERIFIED_TASK_ID"
printf 'drift / inconsistency | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$gateway_status" = "PASS" ] && [ "$ambiguous_status" = "PASS" ] && [ "$delivered_status" = "PASS" ] && [ "$verified_status" = "PASS" ] && [ "$drift_status" = "PASS" ]; then
  printf 'VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_OK gateway=%s ambiguous=%s delivered=%s verified=%s drift=%s report=%s\n' \
    "$GATEWAY_TASK_ID" "$AMBIGUOUS_TASK_ID" "$DELIVERED_TASK_ID" "$VERIFIED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
  exit 0
fi

printf 'VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_FAIL gateway=%s ambiguous=%s delivered=%s verified=%s drift=%s report=%s\n' \
  "$GATEWAY_TASK_ID" "$AMBIGUOUS_TASK_ID" "$DELIVERED_TASK_ID" "$VERIFIED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH" >&2
exit 1
