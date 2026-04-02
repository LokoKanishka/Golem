#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md"
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

[ -f "${DOC}" ] || fail "missing seeds pack doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${DOC}" "## Proposito"
assert_file_contains "${DOC}" "## Alcance"
assert_file_contains "${DOC}" "## Fuera de alcance"
assert_file_contains "${DOC}" "## Relacion con workflow y artifact pack"
assert_file_contains "${DOC}" "## Estructura minima de una seed"
assert_file_contains "${DOC}" "## Seeds canonicas"
assert_file_contains "${DOC}" "quick-reentry-seed"
assert_file_contains "${DOC}" "state-check-seed"
assert_file_contains "${DOC}" "consistency-doc-seed"
assert_file_contains "${DOC}" '`required_inputs`'
assert_file_contains "${DOC}" '`required_artifacts`'
assert_file_contains "${DOC}" '`required_verify`'
assert_file_contains "${DOC}" '`expected_outputs`'
assert_file_contains "${DOC}" '`out_of_scope`'
assert_file_contains "${DOC}" '`kill_criteria`'
assert_file_contains "${DOC}" "## Artifact y verify obligatorias por seed"
assert_file_contains "${DOC}" "## Como transformar una seed en ticket real"
assert_file_contains "${DOC}" "## Cuando usar estas seeds"
assert_file_contains "${DOC}" "## Cuando no alcanzan"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"
assert_file_contains "${DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${DOC}" "./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh"
assert_file_contains "${DOC}" "WhatsApp sigue fuera y congelado"
assert_file_contains "${DOC}" "runtime vivo sigue fuera"
assert_file_contains "${DOC}" "browser nativo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md"

echo "VERIFY_OK: openclaw status snapshot ticket seeds checks passed"
