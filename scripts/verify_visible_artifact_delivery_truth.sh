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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-visible-artifact-delivery-truth.md"

DESKTOP_TASK_ID=""
DOWNLOADS_TASK_ID=""
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
  local source_artifact="$5"
  local summary_output="$6"

  append_report \
    "" \
    "## ${case_name}" \
    "- task_id: ${task_id}" \
    "- verify_status: ${status}" \
    "- note: ${note}" \
    "- source_artifact: ${source_artifact}" \
    "- delivery_summary:" \
    '```text' \
    "$summary_output" \
    '```'
}

create_source_artifact() {
  local slug="$1"
  local title="$2"
  local path="$OUTBOX_DIR/${TIMESTAMP}-${slug}.md"

  python3 - "$path" "$title" <<'PY'
import datetime
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
title = sys.argv[2]
path.write_text(
    "# Visible Artifact Delivery Test\n\n"
    f"generated_at: {datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()}\n"
    f"title: {title}\n\n"
    "This artifact is used to verify user-visible delivery truth.\n",
    encoding="utf-8",
)
print(path)
PY
}

advance_task_to_visible() {
  local task_id="$1"
  local channel="$2"
  local evidence_prefix="$3"

  run_cmd "${evidence_prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-visible-artifact repo-internal 'task submitted into the user-facing artifact lane'"
  run_cmd "${evidence_prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-visible-artifact repo-internal 'technical artifact accepted inside repo staging'"
  run_cmd "${evidence_prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-visible-artifact $channel 'artifact delivery initiated toward the user-facing destination'"
  run_cmd "${evidence_prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-visible-artifact $channel 'delivery evidence should only be claimable after visible artifact verification'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# Visible Artifact Delivery Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that internal staging artifacts and user-visible artifact delivery stay separate.
EOF
}

generate_header

printf '# Visible Artifact Delivery Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

desktop_source_artifact="$(create_source_artifact desktop-source 'Visible artifact delivery truth / desktop')"
run_cmd "Desktop Path / Create Task" "./scripts/task_new.sh verification-visible-artifact 'Verify visible artifact desktop path'"
DESKTOP_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Desktop Path / Move Technical Lifecycle" "./scripts/task_update.sh $DESKTOP_TASK_ID running"
run_cmd "Desktop Path / Technical Close" "./scripts/task_close.sh $DESKTOP_TASK_ID done 'technical artifact generation closed in internal staging'"
advance_task_to_visible "$DESKTOP_TASK_ID" "desktop" "Desktop Path"
run_cmd "Desktop Path / Materialize Visible Artifact" "./scripts/task_materialize_visible_artifact.sh $DESKTOP_TASK_ID $desktop_source_artifact desktop"
desktop_delivery_exit="$LAST_EXIT_CODE"
run_cmd "Desktop Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $DESKTOP_TASK_ID verify-visible-artifact desktop 'final claim after visible artifact delivery verification' 'artifact visible success claim'"
desktop_claim_exit="$LAST_EXIT_CODE"
run_cmd "Desktop Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DESKTOP_TASK_ID"
desktop_summary="$LAST_OUTPUT"

if [ "$desktop_delivery_exit" -eq 0 ] && [ "$desktop_claim_exit" -eq 0 ] && \
   printf '%s\n' "$desktop_summary" | rg -q '^delivery_state: visible$' && \
   printf '%s\n' "$desktop_summary" | rg -q '^visible_artifact_ready: yes$' && \
   printf '%s\n' "$desktop_summary" | rg -q '\| desktop \| PASS \|' && \
   printf '%s\n' "$desktop_summary" | rg -q '^last_user_facing_claim_visible_artifact_ready: yes$'; then
  desktop_status="PASS"
  desktop_note="artifact reached a resolved desktop path, passed visible delivery verification, and authorized the user-facing success claim"
elif [ "$desktop_delivery_exit" -eq 2 ]; then
  desktop_status="BLOCKED"
  desktop_note="desktop target could not be verified as a visible user-facing destination in the current environment"
else
  desktop_status="FAIL"
  desktop_note="desktop visible artifact delivery did not persist a coherent verified path"
fi
record_case_report "Desktop Pass Path" "$DESKTOP_TASK_ID" "$desktop_status" "$desktop_note" "$desktop_source_artifact" "$desktop_summary"

downloads_source_artifact="$(create_source_artifact downloads-source 'Visible artifact delivery truth / downloads')"
run_cmd "Downloads Path / Create Task" "./scripts/task_new.sh verification-visible-artifact 'Verify visible artifact downloads path'"
DOWNLOADS_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Downloads Path / Move Technical Lifecycle" "./scripts/task_update.sh $DOWNLOADS_TASK_ID running"
run_cmd "Downloads Path / Technical Close" "./scripts/task_close.sh $DOWNLOADS_TASK_ID done 'technical artifact generation closed in internal staging'"
advance_task_to_visible "$DOWNLOADS_TASK_ID" "downloads" "Downloads Path"
run_cmd "Downloads Path / Materialize Visible Artifact" "./scripts/task_materialize_visible_artifact.sh $DOWNLOADS_TASK_ID $downloads_source_artifact downloads"
downloads_delivery_exit="$LAST_EXIT_CODE"
run_cmd "Downloads Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $DOWNLOADS_TASK_ID verify-visible-artifact downloads 'final claim after visible artifact delivery verification' 'artifact visible success claim'"
downloads_claim_exit="$LAST_EXIT_CODE"
run_cmd "Downloads Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DOWNLOADS_TASK_ID"
downloads_summary="$LAST_OUTPUT"

if [ "$downloads_delivery_exit" -eq 0 ] && [ "$downloads_claim_exit" -eq 0 ] && \
   printf '%s\n' "$downloads_summary" | rg -q '^delivery_state: visible$' && \
   printf '%s\n' "$downloads_summary" | rg -q '^visible_artifact_ready: yes$' && \
   printf '%s\n' "$downloads_summary" | rg -q '\| downloads \| PASS \|' && \
   printf '%s\n' "$downloads_summary" | rg -q '^last_user_facing_claim_visible_artifact_ready: yes$'; then
  downloads_status="PASS"
  downloads_note="artifact reached a resolved downloads path, passed visible delivery verification, and authorized the user-facing success claim"
elif [ "$downloads_delivery_exit" -eq 2 ]; then
  downloads_status="BLOCKED"
  downloads_note="downloads target could not be verified as a visible user-facing destination in the current environment"
else
  downloads_status="FAIL"
  downloads_note="downloads visible artifact delivery did not persist a coherent verified path"
fi
record_case_report "Downloads Pass Path" "$DOWNLOADS_TASK_ID" "$downloads_status" "$downloads_note" "$downloads_source_artifact" "$downloads_summary"

blocked_source_artifact="$(create_source_artifact blocked-source 'Visible artifact delivery truth / blocked')"
run_cmd "Blocked Path / Create Task" "./scripts/task_new.sh verification-visible-artifact 'Verify visible artifact unverifiable path'"
BLOCKED_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$BLOCKED_TASK_ID" "desktop" "Blocked Path"
run_cmd "Blocked Path / Materialize Visible Artifact" "GOLEM_VISIBLE_ARTIFACT_SIMULATE_UNVERIFIABLE=1 ./scripts/task_materialize_visible_artifact.sh $BLOCKED_TASK_ID $blocked_source_artifact desktop"
blocked_delivery_exit="$LAST_EXIT_CODE"
run_cmd "Blocked Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $BLOCKED_TASK_ID verify-visible-artifact desktop 'attempted final claim even though visible path could not be verified' 'artifact visible success claim'"
blocked_claim_exit="$LAST_EXIT_CODE"
run_cmd "Blocked Path / Delivery Summary" "./scripts/task_delivery_summary.sh $BLOCKED_TASK_ID"
blocked_summary="$LAST_OUTPUT"

if [ "$blocked_delivery_exit" -eq 2 ] && [ "$blocked_claim_exit" -eq 2 ] && \
   printf '%s\n' "$blocked_summary" | rg -q '^delivery_state: visible$' && \
   printf '%s\n' "$blocked_summary" | rg -q '^visible_artifact_ready: no$' && \
   printf '%s\n' "$blocked_summary" | rg -q '\| desktop \| BLOCKED \|' && \
   printf '%s\n' "$blocked_summary" | rg -q '^last_user_facing_claim_visible_artifact_ready: no$'; then
  blocked_status="PASS"
  blocked_note="an unverifiable visible destination stayed BLOCKED and the repo refused the user-facing success claim"
else
  blocked_status="FAIL"
  blocked_note="unverifiable visible artifact delivery was not classified honestly"
fi
record_case_report "Blocked Unverifiable Path" "$BLOCKED_TASK_ID" "$blocked_status" "$blocked_note" "$blocked_source_artifact" "$blocked_summary"

drift_source_artifact="$(create_source_artifact drift-source 'Visible artifact delivery truth / drift')"
drift_dir="$(python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import subprocess
import sys

repo_root = pathlib.Path(sys.argv[1])
cmd = [str(repo_root / "scripts" / "resolve_user_visible_destination.sh"), "desktop", "--json"]
result = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
if result.returncode != 0:
    print("")
else:
    payload = json.loads(result.stdout)
    print(payload.get("absolute_directory", ""))
PY
)"
run_cmd "Drift Path / Create Task" "./scripts/task_new.sh verification-visible-artifact 'Verify visible artifact drift path'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
advance_task_to_visible "$DRIFT_TASK_ID" "desktop" "Drift Path"
if [ -n "$drift_dir" ]; then
  drift_actual_path="$drift_dir/${TIMESTAMP}-drift-actual.md"
  drift_reported_path="$drift_dir/${TIMESTAMP}-drift-reported.md"
  run_cmd "Drift Path / Materialize Visible Artifact" "GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_ACTUAL_PATH='$drift_actual_path' GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_REPORTED_PATH='$drift_reported_path' ./scripts/task_materialize_visible_artifact.sh $DRIFT_TASK_ID $drift_source_artifact desktop"
else
  run_cmd "Drift Path / Materialize Visible Artifact" "./scripts/task_materialize_visible_artifact.sh $DRIFT_TASK_ID $drift_source_artifact desktop"
fi
drift_delivery_exit="$LAST_EXIT_CODE"
run_cmd "Drift Path / Claim User Success" "./scripts/task_claim_user_facing_success.sh $DRIFT_TASK_ID verify-visible-artifact desktop 'attempted final claim after drifted reported path' 'artifact visible success claim'"
drift_claim_exit="$LAST_EXIT_CODE"
run_cmd "Drift Path / Delivery Summary" "./scripts/task_delivery_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ -n "$drift_dir" ] && [ "$drift_delivery_exit" -eq 1 ] && [ "$drift_claim_exit" -eq 2 ] && \
   printf '%s\n' "$drift_summary" | rg -q '^visible_artifact_ready: no$' && \
   printf '%s\n' "$drift_summary" | rg -q '\| desktop \| FAIL \|'; then
  drift_status="PASS"
  drift_note="reported path drift was detected explicitly and prevented a user-facing success claim"
elif [ -z "$drift_dir" ] && [ "$drift_delivery_exit" -eq 2 ]; then
  drift_status="BLOCKED"
  drift_note="drift case could not run because no visible desktop directory was available in the current environment"
else
  drift_status="FAIL"
  drift_note="path drift or visible path inconsistency was not detected as expected"
fi
record_case_report "Drift Detection Path" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_source_artifact" "$drift_summary"

printf '\ncase | status | note | task_id\n'
printf 'desktop visible path | %s | %s | %s\n' "$desktop_status" "$desktop_note" "$DESKTOP_TASK_ID"
printf 'downloads visible path | %s | %s | %s\n' "$downloads_status" "$downloads_note" "$DOWNLOADS_TASK_ID"
printf 'unverifiable path | %s | %s | %s\n' "$blocked_status" "$blocked_note" "$BLOCKED_TASK_ID"
printf 'drift mismatch | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

overall_status="PASS"
if [ "$desktop_status" = "FAIL" ] || [ "$downloads_status" = "FAIL" ] || [ "$blocked_status" = "FAIL" ] || [ "$drift_status" = "FAIL" ]; then
  overall_status="FAIL"
elif [ "$desktop_status" = "BLOCKED" ] || [ "$downloads_status" = "BLOCKED" ] || [ "$drift_status" = "BLOCKED" ]; then
  overall_status="BLOCKED"
fi

case "$overall_status" in
  PASS)
    printf 'VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_OK desktop=%s downloads=%s blocked=%s drift=%s report=%s\n' \
      "$DESKTOP_TASK_ID" "$DOWNLOADS_TASK_ID" "$BLOCKED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
    exit 0
    ;;
  BLOCKED)
    printf 'VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_BLOCKED desktop=%s downloads=%s blocked=%s drift=%s report=%s\n' \
      "$DESKTOP_TASK_ID" "$DOWNLOADS_TASK_ID" "$BLOCKED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH"
    exit 2
    ;;
  *)
    printf 'VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_FAIL desktop=%s downloads=%s blocked=%s drift=%s report=%s\n' \
      "$DESKTOP_TASK_ID" "$DOWNLOADS_TASK_ID" "$BLOCKED_TASK_ID" "$DRIFT_TASK_ID" "$REPORT_PATH" >&2
    exit 1
    ;;
esac
