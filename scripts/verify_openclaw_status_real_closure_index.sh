#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_REAL_CLOSURE_INDEX.md"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing status real closure index doc: ${DOC}"

assert_file_contains "${DOC}" "### quick-reentry"
assert_file_contains "${DOC}" "### state-check"
assert_file_contains "${DOC}" '`closure_doc`'
assert_file_contains "${DOC}" '`artifact_reference`'
assert_file_contains "${DOC}" '`verify_reference`'
assert_file_contains "${DOC}" '`primary_use`'
assert_file_contains "${DOC}" '`do_not_infer`'
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_EXAMPLE.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_STATE_CHECK.md"
assert_file_contains "${DOC}" "outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md"
assert_file_contains "${DOC}" "./scripts/verify_openclaw_status_real_closure_note_example.sh"
assert_file_contains "${DOC}" "reentrada corta del frente `status`"
assert_file_contains "${DOC}" "verdad operativa corta sobre surfaces de `status`"
assert_file_contains "${DOC}" "delivery real"
assert_file_contains "${DOC}" "browser usable"
assert_file_contains "${DOC}" "readiness total"
assert_file_contains "${DOC}" "runtime changes"
assert_file_contains "${DOC}" "reactivar WhatsApp"
assert_file_contains "${DOC}" "si queres reubicarte rapido, leer `quick-reentry`"
assert_file_contains "${DOC}" "si queres una lectura corta de verdad operativa sobre `status`, leer `state-check`"
assert_file_contains "${DOC}" "si necesitas ambas, leer primero `quick-reentry` y despues `state-check`"

echo "VERIFY_OK: openclaw status real closure index checks passed"
