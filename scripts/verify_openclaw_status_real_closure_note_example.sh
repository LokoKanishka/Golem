#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_EXAMPLE.md"
STATE_CHECK_DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_STATE_CHECK.md"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing real closure note example doc: ${DOC}"
[ -f "${STATE_CHECK_DOC}" ] || fail "missing state-check real closure note doc: ${STATE_CHECK_DOC}"

assert_file_contains "${DOC}" '`closure_note_id`'
assert_file_contains "${DOC}" "quick-reentry-closure-note-real-001"
assert_file_contains "${DOC}" '`derived_from_finalization_checklist`'
assert_file_contains "${DOC}" "quick-reentry-finalization-checklist-001"
assert_file_contains "${DOC}" '`artifact_reference`'
assert_file_contains "${DOC}" "outbox/manual/20260402T005229Z_tranche-golem-openclaw-next-execution_local_local_current_state.md"
assert_file_contains "${DOC}" '`verify_cited`'
assert_file_contains "${DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${DOC}" '`brief_evidence_summary`'
assert_file_contains "${DOC}" '`allowed_conclusion`'
assert_file_contains "${DOC}" '`still_forbidden_inferences`'
assert_file_contains "${DOC}" "delivery real"
assert_file_contains "${DOC}" "browser usable"
assert_file_contains "${DOC}" "readiness total"
assert_file_contains "${DOC}" "runtime changes"
assert_file_contains "${DOC}" "reactivar WhatsApp"
assert_file_contains "${DOC}" '`handoff_value`'
assert_file_contains "${DOC}" "lectura operativa corta de reentrada"

assert_file_contains "${STATE_CHECK_DOC}" '`closure_note_id`'
assert_file_contains "${STATE_CHECK_DOC}" "state-check-closure-note-real-001"
assert_file_contains "${STATE_CHECK_DOC}" '`derived_from_finalization_checklist`'
assert_file_contains "${STATE_CHECK_DOC}" "state-check-finalization-checklist-001"
assert_file_contains "${STATE_CHECK_DOC}" '`artifact_reference`'
assert_file_contains "${STATE_CHECK_DOC}" "outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md"
assert_file_contains "${STATE_CHECK_DOC}" '`verify_cited`'
assert_file_contains "${STATE_CHECK_DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${STATE_CHECK_DOC}" "./scripts/verify_openclaw_status_consistency_pack.sh"
assert_file_contains "${STATE_CHECK_DOC}" "./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh"
assert_file_contains "${STATE_CHECK_DOC}" "./scripts/verify_openclaw_status_state_check_closure_gate.sh"
assert_file_contains "${STATE_CHECK_DOC}" '`brief_evidence_summary`'
assert_file_contains "${STATE_CHECK_DOC}" '`allowed_conclusion`'
assert_file_contains "${STATE_CHECK_DOC}" '`still_forbidden_inferences`'
assert_file_contains "${STATE_CHECK_DOC}" "delivery real"
assert_file_contains "${STATE_CHECK_DOC}" "browser usable"
assert_file_contains "${STATE_CHECK_DOC}" "readiness total"
assert_file_contains "${STATE_CHECK_DOC}" "tocar runtime"
assert_file_contains "${STATE_CHECK_DOC}" "reactivar WhatsApp"
assert_file_contains "${STATE_CHECK_DOC}" '`handoff_value`'
assert_file_contains "${STATE_CHECK_DOC}" "verdad operativa corta"

echo "VERIFY_OK: openclaw status real closure note example checks passed"
