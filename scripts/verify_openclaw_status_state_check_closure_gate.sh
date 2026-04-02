#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_STATE_CHECK_CLOSURE_BLOCKED.md"
CURRENT_STATE_DOC="${REPO_ROOT}/docs/CURRENT_STATE.md"
HANDOFF_DOC="${REPO_ROOT}/handoffs/HANDOFF_CURRENT.md"
ARTIFACT="$(find "${REPO_ROOT}/outbox/manual" -maxdepth 1 -type f -name '*_status-triangulation-artifact_state-check.md' | sort | tail -n 1)"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing state-check closure blocked doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"
[ -n "${ARTIFACT}" ] || fail "missing versioned state-check artifact under outbox/manual/"
[ -f "${ARTIFACT}" ] || fail "state-check artifact path is not a file: ${ARTIFACT}"

assert_file_contains "${DOC}" '`UNLOCKED-BY-ARTIFACT`'
assert_file_contains "${DOC}" "status-triangulation-artifact_state-check"
assert_file_contains "${DOC}" 'outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md'
assert_file_contains "${DOC}" "Condicion de desbloqueo"
assert_file_contains "${DOC}" 'reintentar la materializacion del segundo cierre real `state-check`'
assert_file_contains "${DOC}" "tocar runtime"
assert_file_contains "${DOC}" "reactivar WhatsApp"

assert_file_contains "${ARTIFACT}" "status_triangulation_at:"
assert_file_contains "${ARTIFACT}" "artifact_slug: state-check"
assert_file_contains "${ARTIFACT}" "primary_verify: ./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${ARTIFACT}" "primary_verify_result: PASS"
assert_file_contains "${ARTIFACT}" "limitations:"
assert_file_contains "${ARTIFACT}" "no prueba delivery real"
assert_file_contains "${ARTIFACT}" "no prueba browser usable"
assert_file_contains "${ARTIFACT}" "no prueba readiness total"
assert_file_contains "${ARTIFACT}" "no autoriza tocar runtime"
assert_file_contains "${ARTIFACT}" "no autoriza reactivar WhatsApp"
assert_file_contains "${ARTIFACT}" "short_conclusion:"

assert_file_contains "${CURRENT_STATE_DOC}" "outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md"
assert_file_contains "${HANDOFF_DOC}" "outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md"

echo "VERIFY_OK: openclaw status state-check closure gate checks passed"
