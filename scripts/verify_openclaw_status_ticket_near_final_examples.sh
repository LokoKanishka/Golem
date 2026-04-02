#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_TICKET_NEAR_FINAL_EXAMPLES.md"
CURRENT_STATE_DOC="${REPO_ROOT}/docs/CURRENT_STATE.md"
HANDOFF_DOC="${REPO_ROOT}/handoffs/HANDOFF_CURRENT.md"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing near-final examples doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${DOC}" "## Proposito"
assert_file_contains "${DOC}" "## Alcance"
assert_file_contains "${DOC}" "## Fuera de alcance"
assert_file_contains "${DOC}" "## Relacion con completion examples pack"
assert_file_contains "${DOC}" "## Estructura minima de un near-final ticket example"
assert_file_contains "${DOC}" "## Near-final examples canonicos"
assert_file_contains "${DOC}" "quick-reentry-near-final-001"
assert_file_contains "${DOC}" "state-check-near-final-001"
assert_file_contains "${DOC}" '`required_artifact_reference`'
assert_file_contains "${DOC}" '`required_verify`'
assert_file_contains "${DOC}" '`expected_outputs`'
assert_file_contains "${DOC}" '`out_of_scope`'
assert_file_contains "${DOC}" '`kill_criteria`'
assert_file_contains "${DOC}" '`minimal_remaining_placeholders`'
assert_file_contains "${DOC}" "## Artifact y verify por near-final example"
assert_file_contains "${DOC}" "## Como convertir un near-final example en ticket real"
assert_file_contains "${DOC}" "## Cuando usar estos examples"
assert_file_contains "${DOC}" "## Cuando no alcanzan"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_SKELETON_COMPLETION_EXAMPLES.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TICKET_SKELETONS.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_SEED_INSTANTIATION_EXAMPLES.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"
assert_file_contains "${DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${DOC}" "WhatsApp sigue fuera y congelado"
assert_file_contains "${DOC}" "runtime vivo sigue fuera"
assert_file_contains "${DOC}" "browser nativo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_TICKET_NEAR_FINAL_EXAMPLES.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_TICKET_NEAR_FINAL_EXAMPLES.md"

echo "VERIFY_OK: openclaw status ticket near-final examples checks passed"
