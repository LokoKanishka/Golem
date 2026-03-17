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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-host-screenshot-truth.md"

VALID_TASK_ID=""
BLOCKED_TASK_ID=""
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
    "- screenshot_summary:" \
    '```text' \
    "$summary_output" \
    '```'
}

advance_task_to_visible() {
  local task_id="$1"
  local prefix="$2"

  run_cmd "${prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-host-screenshot repo-internal 'task entered the visual evidence lane'"
  run_cmd "${prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-host-screenshot repo-internal 'technical acceptance happened before screenshot verification'"
  run_cmd "${prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-host-screenshot host-screenshot 'visual evidence lane prepared before screenshot verification'"
  run_cmd "${prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-host-screenshot host-screenshot 'generic user-facing truth now depends on verified host screenshot evidence'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# Host Screenshot Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that host-side screenshots are only treated as visual truth after canonical verification.
EOF
}

generate_header

printf '# Host Screenshot Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Valid Screenshot / Create Task" "./scripts/task_new.sh verification-screenshot 'Verify canonical host screenshot capture'"
VALID_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Valid Screenshot / Move Technical Lifecycle" "./scripts/task_update.sh $VALID_TASK_ID running"
run_cmd "Valid Screenshot / Technical Close" "./scripts/task_close.sh $VALID_TASK_ID done 'technical work closed before visual confirmation was verified'"
advance_task_to_visible "$VALID_TASK_ID" "Valid Screenshot"
run_cmd "Valid Screenshot / Capture" "./scripts/task_capture_host_screenshot.sh $VALID_TASK_ID desktop-root - verify-host-screenshot 'captured a real host screenshot for visual evidence' host-screenshot-valid.png"
valid_capture_exit="$LAST_EXIT_CODE"
run_cmd "Valid Screenshot / Claim Before Verify" "./scripts/task_claim_user_facing_success.sh $VALID_TASK_ID verify-host-screenshot host-screenshot 'attempted final visual claim before screenshot verification completed' 'visual confirmation claim'"
valid_preverify_claim_exit="$LAST_EXIT_CODE"
run_cmd "Valid Screenshot / Verify" "./scripts/task_verify_host_screenshot.sh $VALID_TASK_ID latest verify-host-screenshot 'verified host screenshot material identity'"
valid_verify_exit="$LAST_EXIT_CODE"
run_cmd "Valid Screenshot / Claim After Verify" "./scripts/task_claim_user_facing_success.sh $VALID_TASK_ID verify-host-screenshot host-screenshot 'final visual claim after screenshot verification completed' 'visual confirmation claim'"
valid_postverify_claim_exit="$LAST_EXIT_CODE"
run_cmd "Valid Screenshot / Summary" "./scripts/task_screenshot_summary.sh $VALID_TASK_ID"
valid_summary="$LAST_OUTPUT"

if [ "$valid_capture_exit" -eq 0 ] && [ "$valid_preverify_claim_exit" -eq 2 ] && [ "$valid_verify_exit" -eq 0 ] && [ "$valid_postverify_claim_exit" -eq 0 ] && \
   printf '%s\n' "$valid_summary" | rg -q '^screenshot_state: verified$' && \
   printf '%s\n' "$valid_summary" | rg -q '^screenshot_ready_for_claim: yes$'; then
  valid_status="PASS"
  valid_note="host screenshot capture stayed blocked before verification and became claimable only after canonical verification"
else
  valid_status="FAIL"
  valid_note="valid host screenshot flow did not preserve the captured-versus-verified contract"
fi
record_case_report "Valid Screenshot" "$VALID_TASK_ID" "$valid_status" "$valid_note" "$valid_summary"

run_cmd "Blocked Screenshot / Create Task" "./scripts/task_new.sh verification-screenshot 'Verify blocked host screenshot capture'"
BLOCKED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Blocked Screenshot / Capture" "GOLEM_HOST_SCREENSHOT_SIMULATE_BLOCKED=1 ./scripts/task_capture_host_screenshot.sh $BLOCKED_TASK_ID desktop-root - verify-host-screenshot 'host target was not capturable in a controlled blocked fixture' host-screenshot-blocked.png"
blocked_capture_exit="$LAST_EXIT_CODE"
run_cmd "Blocked Screenshot / Summary" "./scripts/task_screenshot_summary.sh $BLOCKED_TASK_ID"
blocked_summary="$LAST_OUTPUT"

if [ "$blocked_capture_exit" -eq 2 ] && printf '%s\n' "$blocked_summary" | rg -q '^screenshot_state: blocked$'; then
  blocked_status="PASS"
  blocked_note="non-capturable host targets stay BLOCKED and do not get upgraded into visual truth"
else
  blocked_status="FAIL"
  blocked_note="blocked host screenshot capture was not classified conservatively"
fi
record_case_report "Blocked Screenshot" "$BLOCKED_TASK_ID" "$blocked_status" "$blocked_note" "$blocked_summary"

run_cmd "Drift Screenshot / Create Task" "./scripts/task_new.sh verification-screenshot 'Verify drifted host screenshot identity'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Drift Screenshot / Capture" "./scripts/task_capture_host_screenshot.sh $DRIFT_TASK_ID desktop-root - verify-host-screenshot 'captured screenshot before mutating its bytes' host-screenshot-drift.png"
drift_capture_exit="$LAST_EXIT_CODE"
drift_path="$(python3 - "$REPO_ROOT/tasks/${DRIFT_TASK_ID}.json" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
items = ((task.get("screenshot") or {}).get("items") or [])
print(items[-1].get("normalized_path", "") if items else "")
PY
)"
python3 - "$drift_path" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
path.write_bytes(path.read_bytes() + b"\nGOLEM_SCREENSHOT_DRIFT\n")
PY
run_cmd "Drift Screenshot / Verify" "./scripts/task_verify_host_screenshot.sh $DRIFT_TASK_ID latest verify-host-screenshot 're-verified after screenshot bytes drifted'"
drift_verify_exit="$LAST_EXIT_CODE"
run_cmd "Drift Screenshot / Summary" "./scripts/task_screenshot_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_capture_exit" -eq 0 ] && [ "$drift_verify_exit" -eq 1 ] && printf '%s\n' "$drift_summary" | rg -q '^screenshot_state: failed$'; then
  drift_status="PASS"
  drift_note="screenshot sha256 drift is detected explicitly and blocks visual truth"
else
  drift_status="FAIL"
  drift_note="screenshot drift did not trigger the expected failed classification"
fi
record_case_report "Drift Screenshot" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

overall_status="PASS"
for case_status in "$valid_status" "$blocked_status" "$drift_status"; do
  if [ "$case_status" != "PASS" ]; then
    overall_status="FAIL"
    break
  fi
done

printf 'case | status | note | task_id\n'
printf 'valid screenshot | %s | %s | %s\n' "$valid_status" "$valid_note" "$VALID_TASK_ID"
printf 'blocked target | %s | %s | %s\n' "$blocked_status" "$blocked_note" "$BLOCKED_TASK_ID"
printf 'drift / mismatch | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$overall_status" = "PASS" ]; then
  printf 'VERIFY_HOST_SCREENSHOT_TRUTH_OK valid=%s blocked=%s drift=%s report=%s\n' "$VALID_TASK_ID" "$BLOCKED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
else
  printf 'VERIFY_HOST_SCREENSHOT_TRUTH_FAIL valid=%s blocked=%s drift=%s report=%s\n' "$VALID_TASK_ID" "$BLOCKED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
  exit 1
fi
