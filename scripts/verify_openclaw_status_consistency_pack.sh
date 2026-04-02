#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"
CURRENT_STATE_DOC="${REPO_ROOT}/docs/CURRENT_STATE.md"
HANDOFF_DOC="${REPO_ROOT}/handoffs/HANDOFF_CURRENT.md"
CAPABILITY_MATRIX_DOC="${REPO_ROOT}/docs/CAPABILITY_MATRIX.md"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing consistency pack doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"
[ -f "${CAPABILITY_MATRIX_DOC}" ] || fail "missing capability matrix doc"

assert_file_contains "${DOC}" "## Proposito"
assert_file_contains "${DOC}" "## Alcance"
assert_file_contains "${DOC}" "## Fuera de alcance"
assert_file_contains "${DOC}" "## Relacion con el status evidence pack"
assert_file_contains "${DOC}" "## Comparacion de las tres superficies"
assert_file_contains "${DOC}" "## Matriz de consistencia"
assert_file_contains "${DOC}" "## Alineaciones y divergencias"
assert_file_contains "${DOC}" "## Evidencia minima de triangulacion"
assert_file_contains "${DOC}" "## Formato recomendado de status triangulation brief"
assert_file_contains "${DOC}" "## Inferencias validas e invalidas"
assert_file_contains "${DOC}" "openclaw gateway status"
assert_file_contains "${DOC}" "openclaw status"
assert_file_contains "${DOC}" "openclaw channels status --probe"
assert_file_contains "${DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${DOC}" "docs/CAPABILITY_MATRIX.md"
assert_file_contains "${DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${DOC}" "WhatsApp sigue congelado"
assert_file_contains "${DOC}" "runtime vivo sigue fuera"
assert_file_contains "${DOC}" "browser nativo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"

echo "VERIFY_OK: openclaw status consistency pack checks passed"
