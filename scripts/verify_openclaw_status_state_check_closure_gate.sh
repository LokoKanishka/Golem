#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_STATE_CHECK_CLOSURE_BLOCKED.md"
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

[ -f "${DOC}" ] || fail "missing state-check closure blocked doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${DOC}" '`BLOCKED-HONESTO`'
assert_file_contains "${DOC}" "status-triangulation-artifact_state-check"
assert_file_contains "${DOC}" 'no existe ninguna artifact versionada con slug `state-check`'
assert_file_contains "${DOC}" 'no existe ninguna `status-triangulation-artifact_*` versionada en git'
assert_file_contains "${DOC}" "Condicion de desbloqueo"
assert_file_contains "${DOC}" "outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md"
assert_file_contains "${DOC}" "No materializar el cierre."
assert_file_contains "${DOC}" "tocar runtime"
assert_file_contains "${DOC}" "reactivar WhatsApp"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_STATE_CHECK_CLOSURE_BLOCKED.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_STATE_CHECK_CLOSURE_BLOCKED.md"

echo "VERIFY_OK: openclaw status state-check closure gate checks passed"
