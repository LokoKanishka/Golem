#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
TIMESTAMP="$(
  python3 - <<'PY'
import datetime
print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
PY
)"
LOG_DIR="$OUTBOX_DIR/${TIMESTAMP}-live-user-journey-logs"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-live-user-journey-smoke.md"

RESULT_NAMES=()
RESULT_STATUSES=()
RESULT_CUTOFFS=()
RESULT_EVIDENCE=()
RESULT_TASK_IDS=()

mkdir -p "$TASKS_DIR" "$OUTBOX_DIR" "$LOG_DIR"

append_result() {
  RESULT_NAMES+=("$1")
  RESULT_STATUSES+=("$2")
  RESULT_CUTOFFS+=("$3")
  RESULT_EVIDENCE+=("$4")
  RESULT_TASK_IDS+=("$5")
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

write_report_header() {
  cat >"$REPORT_PATH" <<EOF
# Live User Journey Smoke

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report runs two real user-facing journeys against the current repo-local system:

- Journey A: visible artifact real
- Journey B: WhatsApp delivery

The smoke reuses the canonical delivery, visible-artifact, WhatsApp, media, and screenshot lanes instead of reimplementing their logic.
EOF
}

run_cmd() {
  local log_path="$1"
  local label="$2"
  local cmd="$3"

  {
    printf '\n## %s\n' "$label"
    printf '$ %s\n' "$cmd"
  } >>"$log_path"

  set +e
  LAST_OUTPUT="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  LAST_EXIT="$?"
  set -e

  printf '%s\n' "$LAST_OUTPUT" >>"$log_path"
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

choose_visible_target() {
  local filename="$1"
  if ./scripts/resolve_user_visible_destination.sh desktop "$filename" --json >/dev/null 2>&1; then
    printf 'desktop\n'
    return 0
  fi
  if ./scripts/resolve_user_visible_destination.sh downloads "$filename" --json >/dev/null 2>&1; then
    printf 'downloads\n'
    return 0
  fi
  printf 'desktop\n'
}

print_section_output() {
  printf '\n## %s\n' "$1"
  printf '%s\n' "$2"
}

write_artifact_file() {
  local artifact_path="$1"
  cat >"$artifact_path" <<EOF
# Live User Journey Smoke Artifact

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This small artifact exists to exercise the canonical visible-artifact and downstream media lanes.
EOF
}

journey_a_visible_artifact() {
  local log_path="$LOG_DIR/journey-a-visible-artifact.log"
  local artifact_filename="${TIMESTAMP}-journey-a-visible-artifact.md"
  local artifact_rel="outbox/manual/${artifact_filename}"
  local artifact_abs="$REPO_ROOT/$artifact_rel"
  local target visible_entry visible_path claim_summary status cutoff evidence task_id visible_result

  : >"$log_path"
  append_report "" "## Journey A" "" "Log: $log_path"

  run_cmd "$log_path" "Journey A / Create Task" "./scripts/task_new.sh live-user-journey 'Live user journey smoke / artifact visible real'"
  task_id="$(printf '%s\n' "$LAST_OUTPUT" | awk '/^TASK_CREATED / {print $2}' | xargs -r basename -s .json)"
  if [ -z "$task_id" ]; then
    append_result "artifact visible real" "FAIL" "task creation failed" "task_id unavailable" ""
    append_report "" "Journey A failed before task creation could be parsed."
    return 0
  fi

  run_cmd "$log_path" "Journey A / Delivery submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted live-user-journey smoke 'journey A requested a user-visible file result'"
  run_cmd "$log_path" "Journey A / Delivery accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted live-user-journey smoke 'journey A accepted the local user-visible file job'"
  run_cmd "$log_path" "Journey A / Delivery delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered live-user-journey smoke 'journey A produced the staged artifact for later visible delivery'"

  write_artifact_file "$artifact_abs"
  run_cmd "$log_path" "Journey A / Validate Artifact" "./scripts/validate_markdown_artifact.sh $artifact_rel"
  run_cmd "$log_path" "Journey A / Register Internal Artifact" "./scripts/task_add_artifact.sh $task_id live-user-journey-artifact $artifact_rel"

  target="$(choose_visible_target "$artifact_filename")"
  run_cmd "$log_path" "Journey A / Materialize Visible Artifact" "./scripts/task_materialize_visible_artifact.sh $task_id $artifact_rel $target --json"
  visible_result="$LAST_EXIT"
  visible_entry="$LAST_OUTPUT"
  visible_path=""
  if [ "$visible_result" -eq 0 ] || [ "$visible_result" -eq 2 ]; then
    visible_path="$(python3 - "$visible_entry" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("resolved_path", ""))
except Exception:
    print("")
PY
)"
  fi

  if [ "$visible_result" -eq 0 ]; then
    run_cmd "$log_path" "Journey A / Delivery visible" "./scripts/task_record_delivery_transition.sh $task_id visible live-user-journey smoke 'journey A verified the user-visible destination after materialization'"
    run_cmd "$log_path" "Journey A / Claim User-Facing Success" "./scripts/task_claim_user_facing_success.sh $task_id live-user-journey smoke 'journey A generic final claim after visible artifact verification' 'final success claim'"
    claim_summary="$LAST_OUTPUT"
    if [ "$LAST_EXIT" -eq 0 ] && printf '%s\n' "$claim_summary" | rg -q '^TASK_USER_FACING_CLAIM_ALLOWED '; then
      status="PASS"
      cutoff="visible artifact delivered and verified"
      evidence="target=$target ; path=$visible_path ; claim=allowed ; artifact=$artifact_rel"
      run_cmd "$log_path" "Journey A / Close Task" "./scripts/task_close.sh $task_id done 'live user journey artifact visible path passed'"
    else
      status="FAIL"
      cutoff="generic final claim stayed blocked after visible artifact verification"
      evidence="target=$target ; path=$visible_path ; claim_output=$(printf '%s' "$claim_summary" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
      run_cmd "$log_path" "Journey A / Close Task" "./scripts/task_close.sh $task_id failed 'live user journey artifact visible path failed at claim gate'"
    fi
  elif [ "$visible_result" -eq 2 ]; then
    status="BLOCKED"
    cutoff="visible destination could not be proven"
    evidence="target=$target ; path=${visible_path:-"(none)"} ; visible_delivery=blocked ; artifact=$artifact_rel"
    run_cmd "$log_path" "Journey A / Close Task" "./scripts/task_close.sh $task_id blocked 'live user journey artifact visible path blocked by visible destination verification'"
  else
    status="FAIL"
    cutoff="visible artifact materialization failed internally"
    evidence="target=$target ; artifact=$artifact_rel ; materialize_exit=$visible_result"
    run_cmd "$log_path" "Journey A / Close Task" "./scripts/task_close.sh $task_id failed 'live user journey artifact visible path failed internally'"
  fi

  JOURNEY_A_TASK_ID="$task_id"
  JOURNEY_A_ARTIFACT_REL="$artifact_rel"
  JOURNEY_A_VISIBLE_PATH="$visible_path"
  append_result "artifact visible real" "$status" "$cutoff" "$evidence" "$task_id"
  append_report "" "### Journey A Summary" "task_id: $task_id" "status: $status" "cutoff: $cutoff" "evidence: $evidence"
}

journey_b_whatsapp_delivery() {
  local log_path="$LOG_DIR/journey-b-whatsapp-delivery.log"
  local task_id media_source media_register_output media_verify_output screenshot_capture_output screenshot_verify_output
  local whatsapp_claim_requested whatsapp_claim_delivered generic_claim_summary status cutoff evidence
  local send_path_output send_path_exit send_path_report send_path_marker
  local wrapper_output wrapper_exit wrapper_status wrapper_report wrapper_state
  local provider_delivery_status provider_delivery_reason
  local canary_output canary_exit canary_report canary_marker

  : >"$log_path"
  append_report "" "## Journey B" "" "Log: $log_path"

  run_cmd "$log_path" "Journey B / Create Task" "./scripts/task_new.sh live-user-journey 'Live user journey smoke / WhatsApp delivery'"
  task_id="$(printf '%s\n' "$LAST_OUTPUT" | awk '/^TASK_CREATED / {print $2}' | xargs -r basename -s .json)"
  if [ -z "$task_id" ]; then
    append_result "whatsapp delivery" "FAIL" "task creation failed" "task_id unavailable" ""
    append_report "" "Journey B failed before task creation could be parsed."
    return 0
  fi

  run_cmd "$log_path" "Journey B / Delivery submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted live-user-journey smoke 'journey B requested a WhatsApp delivery with a real file from journey A'"
  run_cmd "$log_path" "Journey B / Delivery accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted live-user-journey smoke 'journey B accepted the WhatsApp-oriented user request locally'"
  run_cmd "$log_path" "Journey B / Delivery delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered live-user-journey smoke 'journey B prepared the file and entered the outbound delivery lane locally'"
  run_cmd "$log_path" "Journey B / Delivery visible" "./scripts/task_record_delivery_transition.sh $task_id visible live-user-journey smoke 'journey B already has a locally visible prepared file before channel confirmation'"

  media_source="$JOURNEY_A_VISIBLE_PATH"
  if [ -z "$media_source" ] || [ ! -f "$media_source" ]; then
    media_source="$REPO_ROOT/$JOURNEY_A_ARTIFACT_REL"
  fi

  run_cmd "$log_path" "Journey B / Register Media" "./scripts/task_register_media_ingestion.sh $task_id local-path '$media_source' live-user-journey 'journey B ingested the real artifact prepared by journey A' --json"
  media_register_output="$LAST_OUTPUT"
  if [ "$LAST_EXIT" -ne 0 ]; then
    if [ "$LAST_EXIT" -eq 2 ]; then
      status="BLOCKED"
      cutoff="media ingestion could not prove a readable file identity"
      evidence="source=$media_source ; media_state=blocked"
      run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id blocked 'live user journey WhatsApp path blocked during media registration'"
    else
      status="FAIL"
      cutoff="media registration failed internally"
      evidence="source=$media_source ; register_exit=$LAST_EXIT"
      run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id failed 'live user journey WhatsApp path failed during media registration'"
    fi
    append_result "whatsapp delivery" "$status" "$cutoff" "$evidence" "$task_id"
    append_report "" "### Journey B Summary" "task_id: $task_id" "status: $status" "cutoff: $cutoff" "evidence: $evidence"
    return 0
  fi

  run_cmd "$log_path" "Journey B / Verify Media" "./scripts/task_verify_media_ready.sh $task_id latest live-user-journey 'journey B verified the media identity before channel delivery' --json"
  media_verify_output="$LAST_OUTPUT"
  if [ "$LAST_EXIT" -ne 0 ]; then
    if [ "$LAST_EXIT" -eq 2 ]; then
      status="BLOCKED"
      cutoff="media identity could not be verified reliably"
      evidence="source=$media_source ; media_state=blocked"
      run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id blocked 'live user journey WhatsApp path blocked during media verification'"
    else
      status="FAIL"
      cutoff="media identity drifted or failed verification"
      evidence="source=$media_source ; media_state=failed"
      run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id failed 'live user journey WhatsApp path failed during media verification'"
    fi
    append_result "whatsapp delivery" "$status" "$cutoff" "$evidence" "$task_id"
    append_report "" "### Journey B Summary" "task_id: $task_id" "status: $status" "cutoff: $cutoff" "evidence: $evidence"
    return 0
  fi

  run_cmd "$log_path" "Journey B / Verify WhatsApp Live Send Path" "bash ./scripts/verify_whatsapp_live_send_path.sh"
  send_path_output="$LAST_OUTPUT"
  send_path_exit="$LAST_EXIT"
  send_path_report="$(python3 - "$send_path_output" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'^report_path: (\S+)$', text, re.MULTILINE)
if match:
    print(match.group(1))
    raise SystemExit(0)
match = re.search(r'^VERIFY_WHATSAPP_LIVE_SEND_PATH_(?:OK|BLOCKED|FAIL)\b.*\breport=(\S+)', text, re.MULTILINE)
print(match.group(1) if match else "")
PY
)"
  send_path_marker="$(printf '%s\n' "$send_path_output" | awk '/^VERIFY_WHATSAPP_LIVE_SEND_PATH_(OK|BLOCKED|FAIL) / {print $1}' | tail -n 1)"

  run_cmd "$log_path" "Journey B / Verify WhatsApp Live Provider Canary" "bash ./scripts/verify_whatsapp_live_provider_canary.sh"
  canary_output="$LAST_OUTPUT"
  canary_exit="$LAST_EXIT"
  canary_report="$(python3 - "$canary_output" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'^report_path: (\S+)$', text, re.MULTILINE)
if match:
    print(match.group(1))
    raise SystemExit(0)
match = re.search(r'^VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_(?:OK|BLOCKED|FAIL)\b.*\breport=(\S+)', text, re.MULTILINE)
print(match.group(1) if match else "")
PY
)"
  canary_marker="$(printf '%s\n' "$canary_output" | awk '/^VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_(OK|BLOCKED|FAIL) / {print $1}' | tail -n 1)"

  run_cmd "$log_path" "Journey B / Canonical WhatsApp Wrapper" "./scripts/task_send_whatsapp_live.sh $task_id +5491100000007 --message 'Live user journey smoke / WhatsApp delivery' --media '$media_source' --dry-run --json"
  wrapper_output="$LAST_OUTPUT"
  wrapper_exit="$LAST_EXIT"
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

  run_cmd "$log_path" "Journey B / Claim WhatsApp requested wording" "./scripts/task_claim_whatsapp_delivery.sh $task_id live-user-journey requested 'journey B degrades the WhatsApp wording to the exact requested-only evidence level'"
  whatsapp_claim_requested="$LAST_OUTPUT"
  run_cmd "$log_path" "Journey B / Claim WhatsApp delivered wording" "./scripts/task_claim_whatsapp_delivery.sh $task_id live-user-journey delivered 'journey B attempted a delivered wording without gateway/provider proof'"
  whatsapp_claim_delivered="$LAST_OUTPUT"
  run_cmd "$log_path" "Journey B / Claim Generic Final Success" "./scripts/task_claim_user_facing_success.sh $task_id live-user-journey smoke 'journey B attempted a generic final success without verified WhatsApp delivery' 'final success claim'"
  generic_claim_summary="$LAST_OUTPUT"

  provider_delivery_status="$(task_field "$task_id" delivery.whatsapp.provider_delivery_status)"
  provider_delivery_reason="$(task_field "$task_id" delivery.whatsapp.provider_delivery_reason)"

  status="BLOCKED"
  cutoff="canonical live send path exists, but the controlled live provider canary still did not prove delivered state"
  evidence="source=$media_source ; whatsapp_state=$(task_field "$task_id" delivery.whatsapp.current_state) ; provider_delivery_status=$provider_delivery_status ; provider_delivery_reason=$provider_delivery_reason ; allowed_claim=$(task_field "$task_id" delivery.whatsapp.allowed_user_facing_claim) ; wrapper_state=$wrapper_state ; wrapper_status=$wrapper_status ; delivered_claim=blocked ; generic_claim=blocked ; live_send_path_verify=$send_path_marker ; live_send_path_report=$send_path_report ; live_provider_canary_verify=$canary_marker ; live_provider_canary_report=$canary_report ; wrapper_report=$wrapper_report"

  if ! printf '%s\n' "$whatsapp_claim_requested" | rg -q '^TASK_WHATSAPP_CLAIM_ALLOWED '; then
    status="FAIL"
    cutoff="requested-level WhatsApp wording was not claimable conservatively"
    evidence="source=$media_source ; requested_claim_output=$(printf '%s' "$whatsapp_claim_requested" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
  elif [ "$wrapper_exit" -eq 1 ] || [ "$wrapper_status" = "FAIL" ]; then
    status="FAIL"
    cutoff="the canonical WhatsApp wrapper detected an internal inconsistency or evidence drift"
    evidence="source=$media_source ; wrapper_output=$(printf '%s' "$wrapper_output" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g') ; wrapper_report=$wrapper_report"
  elif [ "$canary_exit" -eq 1 ] || [ "$canary_marker" = "VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_FAIL" ]; then
    status="FAIL"
    cutoff="the controlled live provider canary failed internally or exposed an inconsistency"
    evidence="source=$media_source ; live_provider_canary_verify=$canary_marker ; live_provider_canary_report=$canary_report"
  elif [ "$canary_exit" -eq 0 ] && [ "$canary_marker" = "VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_OK" ]; then
    status="PASS"
    cutoff="the controlled live provider canary proved delivered WhatsApp truth and Journey B now clears the last provider-proof blocker"
    evidence="source=$media_source ; wrapper_state=$wrapper_state ; wrapper_status=$wrapper_status ; live_send_path_verify=$send_path_marker ; live_send_path_report=$send_path_report ; live_provider_canary_verify=$canary_marker ; live_provider_canary_report=$canary_report ; wrapper_report=$wrapper_report"
  elif ! printf '%s\n' "$whatsapp_claim_delivered" | rg -q '^TASK_WHATSAPP_CLAIM_BLOCKED '; then
    status="FAIL"
    cutoff="delivered-level WhatsApp wording was not blocked despite missing delivery proof"
    evidence="source=$media_source ; delivered_claim_output=$(printf '%s' "$whatsapp_claim_delivered" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
  elif ! printf '%s\n' "$generic_claim_summary" | rg -q '^TASK_USER_FACING_CLAIM_BLOCKED '; then
    status="FAIL"
    cutoff="generic final success was not blocked despite missing WhatsApp delivery proof"
    evidence="source=$media_source ; generic_claim_output=$(printf '%s' "$generic_claim_summary" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
  elif [ "$send_path_exit" -eq 1 ] || [ "$send_path_marker" = "VERIFY_WHATSAPP_LIVE_SEND_PATH_FAIL" ]; then
    status="FAIL"
    cutoff="the canonical WhatsApp live send path verify failed internally"
    evidence="source=$media_source ; live_send_path_verify=$send_path_marker ; live_send_path_report=$send_path_report"
  elif [ "$wrapper_exit" -eq 2 ] || [ "$wrapper_status" = "BLOCKED" ]; then
    status="BLOCKED"
    cutoff="the canonical wrapper exists, but this smoke stayed blocked before any auditable gateway or provider delivery evidence"
    evidence="source=$media_source ; whatsapp_state=$(task_field "$task_id" delivery.whatsapp.current_state) ; provider_delivery_status=$provider_delivery_status ; provider_delivery_reason=$provider_delivery_reason ; allowed_claim=$(task_field "$task_id" delivery.whatsapp.allowed_user_facing_claim) ; wrapper_state=$wrapper_state ; wrapper_status=$wrapper_status ; live_send_path_verify=$send_path_marker ; live_send_path_report=$send_path_report ; live_provider_canary_verify=$canary_marker ; live_provider_canary_report=$canary_report ; wrapper_report=$wrapper_report"
  elif [ "$canary_exit" -eq 2 ] && [ "$canary_marker" = "VERIFY_WHATSAPP_LIVE_PROVIDER_CANARY_BLOCKED" ]; then
    status="BLOCKED"
    cutoff="a canonical live send path exists, but the controlled live provider canary remained blocked because provider proof is still missing or unavailable"
    evidence="source=$media_source ; whatsapp_state=$(task_field "$task_id" delivery.whatsapp.current_state) ; provider_delivery_status=$provider_delivery_status ; provider_delivery_reason=$provider_delivery_reason ; allowed_claim=$(task_field "$task_id" delivery.whatsapp.allowed_user_facing_claim) ; wrapper_state=$wrapper_state ; wrapper_status=$wrapper_status ; live_send_path_verify=$send_path_marker ; live_send_path_report=$send_path_report ; live_provider_canary_verify=$canary_marker ; live_provider_canary_report=$canary_report ; wrapper_report=$wrapper_report"
  fi

  if [ "$status" = "PASS" ]; then
    run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id done 'live user journey WhatsApp path passed after the live provider canary proved delivery capability'"
  elif [ "$status" = "BLOCKED" ]; then
    run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id blocked 'live user journey WhatsApp path blocked before any live gateway/provider delivery proof'"
  else
    run_cmd "$log_path" "Journey B / Close Task" "./scripts/task_close.sh $task_id failed 'live user journey WhatsApp path failed semantically'"
  fi

  append_result "whatsapp delivery" "$status" "$cutoff" "$evidence" "$task_id"
  append_report "" "### Journey B Summary" "task_id: $task_id" "status: $status" "cutoff: $cutoff" "evidence: $evidence"
}

cd "$REPO_ROOT"
write_report_header

printf '# Live User Journey Smoke\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

JOURNEY_A_TASK_ID=""
JOURNEY_A_ARTIFACT_REL=""
JOURNEY_A_VISIBLE_PATH=""

journey_a_visible_artifact
journey_b_whatsapp_delivery

pass_count=0
blocked_count=0
fail_count=0
for status in "${RESULT_STATUSES[@]}"; do
  case "$status" in
    PASS) pass_count=$((pass_count + 1)) ;;
    BLOCKED) blocked_count=$((blocked_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
  esac
done

overall_status="PASS"
overall_note="both real user journeys completed coherently"
if [ "$fail_count" -gt 0 ]; then
  overall_status="FAIL"
  overall_note="at least one real user journey failed internally or exposed a semantic inconsistency"
elif [ "$blocked_count" -gt 0 ]; then
  overall_status="BLOCKED"
  overall_note="at least one real user journey remains blocked even though no internal inconsistency was detected"
fi

printf '\njourney | status | cutoff | evidence | task_id\n'
append_report "" "## Aggregated Results" "journey | status | cutoff | evidence | task_id"
for index in "${!RESULT_NAMES[@]}"; do
  printf '%s | %s | %s | %s | %s\n' \
    "${RESULT_NAMES[$index]}" \
    "${RESULT_STATUSES[$index]}" \
    "${RESULT_CUTOFFS[$index]}" \
    "${RESULT_EVIDENCE[$index]}" \
    "${RESULT_TASK_IDS[$index]}"
  append_report "${RESULT_NAMES[$index]} | ${RESULT_STATUSES[$index]} | ${RESULT_CUTOFFS[$index]} | ${RESULT_EVIDENCE[$index]} | ${RESULT_TASK_IDS[$index]}"
done

printf 'PASS: %s\n' "$pass_count"
printf 'FAIL: %s\n' "$fail_count"
printf 'BLOCKED: %s\n' "$blocked_count"
printf 'overall_status: %s\n' "$overall_status"
printf 'overall_note: %s\n' "$overall_note"
printf 'report_path: %s\n' "$REPORT_PATH"

append_report "" "PASS: $pass_count" "FAIL: $fail_count" "BLOCKED: $blocked_count" "overall_status: $overall_status" "overall_note: $overall_note"

if [ "$fail_count" -gt 0 ]; then
  printf 'VERIFY_LIVE_USER_JOURNEY_SMOKE_FAIL pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
  exit 1
fi

if [ "$blocked_count" -gt 0 ]; then
  printf 'VERIFY_LIVE_USER_JOURNEY_SMOKE_BLOCKED pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
  exit 2
fi

printf 'VERIFY_LIVE_USER_JOURNEY_SMOKE_OK pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
