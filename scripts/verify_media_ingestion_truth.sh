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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-media-ingestion-truth.md"

INTERNAL_TASK_ID=""
VISIBLE_TASK_ID=""
LOCAL_TASK_ID=""
MISSING_TASK_ID=""
DRIFT_TASK_ID=""
DIRECTORY_TASK_ID=""

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
    "- media_summary:" \
    '```text' \
    "$summary_output" \
    '```'
}

create_media_file() {
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
    "# Media Ingestion Truth Test\n\n"
    f"generated_at: {datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()}\n"
    f"title: {title}\n\n"
    "This file is used to verify canonical media ingestion.\n",
    encoding="utf-8",
)
print(path)
PY
}

advance_task_to_visible() {
  local task_id="$1"
  local prefix="$2"
  local channel="${3:-repo-internal}"

  run_cmd "${prefix} / submitted" "./scripts/task_record_delivery_transition.sh $task_id submitted verify-media-ingestion repo-internal 'task entered the outbound lane'"
  run_cmd "${prefix} / accepted" "./scripts/task_record_delivery_transition.sh $task_id accepted verify-media-ingestion repo-internal 'technical output accepted before media readiness'"
  run_cmd "${prefix} / delivered" "./scripts/task_record_delivery_transition.sh $task_id delivered verify-media-ingestion $channel 'delivery lane prepared before media readiness is proven'"
  run_cmd "${prefix} / visible" "./scripts/task_record_delivery_transition.sh $task_id visible verify-media-ingestion $channel 'generic user-facing truth now depends on canonical media verification'"
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# Media Ingestion Truth Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report verifies that media is ingested with a canonical material identity before it can be treated as ready for downstream delivery.
EOF
}

generate_header

printf '# Media Ingestion Truth Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

internal_artifact="$(create_media_file internal-artifact 'Media ingestion truth / internal artifact')"
run_cmd "Internal Artifact Path / Create Task" "./scripts/task_new.sh verification-media 'Verify internal artifact media ingestion'"
INTERNAL_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Internal Artifact Path / Move Technical Lifecycle" "./scripts/task_update.sh $INTERNAL_TASK_ID running"
run_cmd "Internal Artifact Path / Technical Close" "./scripts/task_close.sh $INTERNAL_TASK_ID done 'technical artifact generation completed before media ingestion'"
run_cmd "Internal Artifact Path / Register Artifact" "./scripts/task_add_artifact.sh $INTERNAL_TASK_ID internal-test-artifact $internal_artifact"
advance_task_to_visible "$INTERNAL_TASK_ID" "Internal Artifact Path"
run_cmd "Internal Artifact Path / Register Media" "./scripts/task_register_media_ingestion.sh $INTERNAL_TASK_ID task-artifact $internal_artifact verify-media-ingestion 'registered internal artifact as canonical media candidate'"
internal_register_exit="$LAST_EXIT_CODE"
run_cmd "Internal Artifact Path / Claim Before Verify" "./scripts/task_claim_user_facing_success.sh $INTERNAL_TASK_ID verify-media-ingestion repo-internal 'attempted final success before media verification completed' 'final success claim'"
internal_preverify_claim_exit="$LAST_EXIT_CODE"
run_cmd "Internal Artifact Path / Verify Media" "./scripts/task_verify_media_ready.sh $INTERNAL_TASK_ID latest verify-media-ingestion 'verified internal artifact material identity'"
internal_verify_exit="$LAST_EXIT_CODE"
run_cmd "Internal Artifact Path / Claim After Verify" "./scripts/task_claim_user_facing_success.sh $INTERNAL_TASK_ID verify-media-ingestion repo-internal 'final success after media verification completed' 'final success claim'"
internal_postverify_claim_exit="$LAST_EXIT_CODE"
run_cmd "Internal Artifact Path / Media Summary" "./scripts/task_media_summary.sh $INTERNAL_TASK_ID"
internal_summary="$LAST_OUTPUT"

if [ "$internal_register_exit" -eq 0 ] && [ "$internal_preverify_claim_exit" -eq 2 ] && [ "$internal_verify_exit" -eq 0 ] && [ "$internal_postverify_claim_exit" -eq 0 ] && \
   printf '%s\n' "$internal_summary" | rg -q '^media_state: verified$' && \
   printf '%s\n' "$internal_summary" | rg -q 'task-artifact'; then
  internal_status="PASS"
  internal_note="internal task artifact was ingested canonically, blocked final claims before verification, and became ready only after identity verification"
else
  internal_status="FAIL"
  internal_note="internal artifact media ingestion did not preserve canonical registration, verification, and claim gating"
fi
record_case_report "Internal Artifact Path" "$INTERNAL_TASK_ID" "$internal_status" "$internal_note" "$internal_summary"

visible_source_artifact="$(create_media_file visible-artifact 'Media ingestion truth / visible artifact')"
run_cmd "Visible Artifact Path / Create Task" "./scripts/task_new.sh verification-media 'Verify visible artifact media ingestion'"
VISIBLE_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Visible Artifact Path / Move Technical Lifecycle" "./scripts/task_update.sh $VISIBLE_TASK_ID running"
run_cmd "Visible Artifact Path / Technical Close" "./scripts/task_close.sh $VISIBLE_TASK_ID done 'technical artifact generation completed before visible materialization'"
advance_task_to_visible "$VISIBLE_TASK_ID" "Visible Artifact Path" "desktop"
run_cmd "Visible Artifact Path / Materialize Visible Artifact" "./scripts/task_materialize_visible_artifact.sh $VISIBLE_TASK_ID $visible_source_artifact desktop"
visible_materialize_exit="$LAST_EXIT_CODE"
visible_materialized_path="$(python3 - "$REPO_ROOT/tasks/${VISIBLE_TASK_ID}.json" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
deliveries = ((task.get("delivery") or {}).get("visible_artifact_deliveries") or [])
print(deliveries[-1].get("resolved_path", "") if deliveries else "")
PY
)"
run_cmd "Visible Artifact Path / Register Media" "./scripts/task_register_media_ingestion.sh $VISIBLE_TASK_ID visible-artifact '$visible_materialized_path' verify-media-ingestion 'registered verified visible artifact as media candidate'"
visible_register_exit="$LAST_EXIT_CODE"
run_cmd "Visible Artifact Path / Verify Media" "./scripts/task_verify_media_ready.sh $VISIBLE_TASK_ID latest verify-media-ingestion 'verified visible artifact material identity'"
visible_verify_exit="$LAST_EXIT_CODE"
run_cmd "Visible Artifact Path / Media Summary" "./scripts/task_media_summary.sh $VISIBLE_TASK_ID"
visible_summary="$LAST_OUTPUT"

if [ "$visible_materialize_exit" -eq 0 ] && [ "$visible_register_exit" -eq 0 ] && [ "$visible_verify_exit" -eq 0 ] && \
   printf '%s\n' "$visible_summary" | rg -q '^media_state: verified$' && \
   printf '%s\n' "$visible_summary" | rg -q 'visible-artifact'; then
  visible_status="PASS"
  visible_note="verified visible artifact paths can be re-ingested as canonical media with stable identity"
else
  visible_status="FAIL"
  visible_note="visible artifact media ingestion did not preserve the verified visible path semantics"
fi
record_case_report "Visible Artifact Path" "$VISIBLE_TASK_ID" "$visible_status" "$visible_note" "$visible_summary"

local_media_path="$(create_media_file local-path 'Media ingestion truth / local path')"
run_cmd "Local Path / Create Task" "./scripts/task_new.sh verification-media 'Verify local path media ingestion'"
LOCAL_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Local Path / Register Media" "./scripts/task_register_media_ingestion.sh $LOCAL_TASK_ID local-path $local_media_path verify-media-ingestion 'registered explicit local path as media candidate'"
local_register_exit="$LAST_EXIT_CODE"
run_cmd "Local Path / Verify Media" "./scripts/task_verify_media_ready.sh $LOCAL_TASK_ID latest verify-media-ingestion 'verified explicit local path material identity'"
local_verify_exit="$LAST_EXIT_CODE"
run_cmd "Local Path / Media Summary" "./scripts/task_media_summary.sh $LOCAL_TASK_ID"
local_summary="$LAST_OUTPUT"

if [ "$local_register_exit" -eq 0 ] && [ "$local_verify_exit" -eq 0 ] && \
   printf '%s\n' "$local_summary" | rg -q '^media_state: verified$' && \
   printf '%s\n' "$local_summary" | rg -q 'local-path'; then
  local_status="PASS"
  local_note="explicit local paths can be ingested canonically when they remain readable files"
else
  local_status="FAIL"
  local_note="local path media ingestion did not preserve canonical verification"
fi
record_case_report "Local Path" "$LOCAL_TASK_ID" "$local_status" "$local_note" "$local_summary"

missing_path="$OUTBOX_DIR/${TIMESTAMP}-missing-media.md"
run_cmd "Missing Path / Create Task" "./scripts/task_new.sh verification-media 'Verify missing media path'"
MISSING_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Missing Path / Register Media" "./scripts/task_register_media_ingestion.sh $MISSING_TASK_ID local-path $missing_path verify-media-ingestion 'attempted to ingest a missing path'"
missing_register_exit="$LAST_EXIT_CODE"
run_cmd "Missing Path / Media Summary" "./scripts/task_media_summary.sh $MISSING_TASK_ID"
missing_summary="$LAST_OUTPUT"

if [ "$missing_register_exit" -eq 2 ] && printf '%s\n' "$missing_summary" | rg -q '^media_state: blocked$'; then
  missing_status="PASS"
  missing_note="missing media paths stay blocked instead of being treated as canonical ready media"
else
  missing_status="FAIL"
  missing_note="missing media paths were not classified conservatively"
fi
record_case_report "Missing Path" "$MISSING_TASK_ID" "$missing_status" "$missing_note" "$missing_summary"

drift_media_path="$(create_media_file drift-path 'Media ingestion truth / drift path')"
run_cmd "Drift Path / Create Task" "./scripts/task_new.sh verification-media 'Verify drifted media identity'"
DRIFT_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Drift Path / Register Media" "./scripts/task_register_media_ingestion.sh $DRIFT_TASK_ID local-path $drift_media_path verify-media-ingestion 'registered local file before drifting its contents'"
drift_register_exit="$LAST_EXIT_CODE"
python3 - "$drift_media_path" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8") + "\ncontent drift injected after registration\n", encoding="utf-8")
PY
run_cmd "Drift Path / Verify Media" "./scripts/task_verify_media_ready.sh $DRIFT_TASK_ID latest verify-media-ingestion 're-verified after the file contents drifted'"
drift_verify_exit="$LAST_EXIT_CODE"
run_cmd "Drift Path / Media Summary" "./scripts/task_media_summary.sh $DRIFT_TASK_ID"
drift_summary="$LAST_OUTPUT"

if [ "$drift_register_exit" -eq 0 ] && [ "$drift_verify_exit" -eq 1 ] && \
   printf '%s\n' "$drift_summary" | rg -q '^media_state: failed$'; then
  drift_status="PASS"
  drift_note="material identity drift was detected explicitly through the stored canonical sha256"
else
  drift_status="FAIL"
  drift_note="media identity drift was not detected as expected"
fi
record_case_report "Drift Path" "$DRIFT_TASK_ID" "$drift_status" "$drift_note" "$drift_summary"

run_cmd "Directory Path / Create Task" "./scripts/task_new.sh verification-media 'Verify directory media rejection'"
DIRECTORY_TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
run_cmd "Directory Path / Register Media" "./scripts/task_register_media_ingestion.sh $DIRECTORY_TASK_ID local-path $OUTBOX_DIR verify-media-ingestion 'attempted to ingest a directory as media'"
directory_register_exit="$LAST_EXIT_CODE"
run_cmd "Directory Path / Media Summary" "./scripts/task_media_summary.sh $DIRECTORY_TASK_ID"
directory_summary="$LAST_OUTPUT"

if [ "$directory_register_exit" -eq 1 ] && printf '%s\n' "$directory_summary" | rg -q '^media_state: failed$'; then
  directory_status="PASS"
  directory_note="directories are rejected explicitly instead of being treated as canonical media files"
else
  directory_status="FAIL"
  directory_note="directory ingestion did not fail explicitly as expected"
fi
record_case_report "Directory Path" "$DIRECTORY_TASK_ID" "$directory_status" "$directory_note" "$directory_summary"

printf '\ncase | status | note | task_id\n'
printf 'internal artifact | %s | %s | %s\n' "$internal_status" "$internal_note" "$INTERNAL_TASK_ID"
printf 'visible artifact | %s | %s | %s\n' "$visible_status" "$visible_note" "$VISIBLE_TASK_ID"
printf 'local path | %s | %s | %s\n' "$local_status" "$local_note" "$LOCAL_TASK_ID"
printf 'missing path | %s | %s | %s\n' "$missing_status" "$missing_note" "$MISSING_TASK_ID"
printf 'drift / mismatch | %s | %s | %s\n' "$drift_status" "$drift_note" "$DRIFT_TASK_ID"
printf 'directory instead of file | %s | %s | %s\n' "$directory_status" "$directory_note" "$DIRECTORY_TASK_ID"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$internal_status" = "PASS" ] && [ "$visible_status" = "PASS" ] && [ "$local_status" = "PASS" ] && [ "$missing_status" = "PASS" ] && [ "$drift_status" = "PASS" ] && [ "$directory_status" = "PASS" ]; then
  printf 'VERIFY_MEDIA_INGESTION_TRUTH_OK internal=%s visible=%s local=%s missing=%s drift=%s directory=%s report=%s\n' \
    "$INTERNAL_TASK_ID" "$VISIBLE_TASK_ID" "$LOCAL_TASK_ID" "$MISSING_TASK_ID" "$DRIFT_TASK_ID" "$DIRECTORY_TASK_ID" "$REPORT_PATH"
  exit 0
fi

printf 'VERIFY_MEDIA_INGESTION_TRUTH_FAIL internal=%s visible=%s local=%s missing=%s drift=%s directory=%s report=%s\n' \
  "$INTERNAL_TASK_ID" "$VISIBLE_TASK_ID" "$LOCAL_TASK_ID" "$MISSING_TASK_ID" "$DRIFT_TASK_ID" "$DIRECTORY_TASK_ID" "$REPORT_PATH" >&2
exit 1
