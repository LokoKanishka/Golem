#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_PACK_DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"
CAPABILITY_MATRIX_DOC="${REPO_ROOT}/docs/CAPABILITY_MATRIX.md"
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

[ -f "${STATUS_PACK_DOC}" ] || fail "missing status pack doc: ${STATUS_PACK_DOC}"
[ -f "${CAPABILITY_MATRIX_DOC}" ] || fail "missing capability matrix doc"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${STATUS_PACK_DOC}" "## Proposito"
assert_file_contains "${STATUS_PACK_DOC}" "## Alcance"
assert_file_contains "${STATUS_PACK_DOC}" "## Fuera de alcance"
assert_file_contains "${STATUS_PACK_DOC}" "## Relacion con baseline pack y mapping pack"
assert_file_contains "${STATUS_PACK_DOC}" '## Que cuenta como evidencia valida de `status`'
assert_file_contains "${STATUS_PACK_DOC}" "## Matriz de evidencia minima"
assert_file_contains "${STATUS_PACK_DOC}" "## Formato recomendado de status brief"
assert_file_contains "${STATUS_PACK_DOC}" "## Inferencias validas"
assert_file_contains "${STATUS_PACK_DOC}" "## Inferencias invalidas"
assert_file_contains "${STATUS_PACK_DOC}" "## Como usar este pack para retome rapido"
assert_file_contains "${STATUS_PACK_DOC}" "docs/CAPABILITY_MATRIX.md"
assert_file_contains "${STATUS_PACK_DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${STATUS_PACK_DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${STATUS_PACK_DOC}" "./scripts/verify_openclaw_capability_truth.sh"
assert_file_contains "${STATUS_PACK_DOC}" "WhatsApp sigue fuera y congelado"
assert_file_contains "${STATUS_PACK_DOC}" "browser nativo sigue fuera"
assert_file_contains "${STATUS_PACK_DOC}" "runtime vivo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"

echo "VERIFY_OK: openclaw status evidence pack checks passed"
