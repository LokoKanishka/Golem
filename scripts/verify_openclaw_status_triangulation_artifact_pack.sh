#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"
CURRENT_STATE_DOC="${REPO_ROOT}/docs/CURRENT_STATE.md"
HANDOFF_DOC="${REPO_ROOT}/handoffs/HANDOFF_CURRENT.md"
HELPER="${REPO_ROOT}/scripts/render_status_triangulation_artifact.sh"

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

[ -f "${DOC}" ] || fail "missing artifact pack doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"
[ -x "${HELPER}" ] || fail "missing executable helper: ${HELPER}"

assert_file_contains "${DOC}" "## Proposito"
assert_file_contains "${DOC}" "## Alcance"
assert_file_contains "${DOC}" "## Fuera de alcance"
assert_file_contains "${DOC}" "## Relacion con status evidence pack y status consistency pack"
assert_file_contains "${DOC}" "## Definicion exacta del artifact"
assert_file_contains "${DOC}" "## Formato canonico del artifact"
assert_file_contains "${DOC}" "## Convencion de nombres y rutas"
assert_file_contains "${DOC}" "## Cuando usarlo"
assert_file_contains "${DOC}" "## Cuando no alcanza"
assert_file_contains "${DOC}" "## Helper minima recomendada"
assert_file_contains "${DOC}" "## Inferencias validas e invalidas"
assert_file_contains "${DOC}" 'status_triangulation_at'
assert_file_contains "${DOC}" 'openclaw gateway status'
assert_file_contains "${DOC}" 'openclaw status'
assert_file_contains "${DOC}" 'openclaw channels status --probe'
assert_file_contains "${DOC}" 'docs/OPENCLAW_STATUS_EVIDENCE_PACK.md'
assert_file_contains "${DOC}" 'docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md'
assert_file_contains "${DOC}" 'docs/CURRENT_STATE.md'
assert_file_contains "${DOC}" 'handoffs/HANDOFF_CURRENT.md'
assert_file_contains "${DOC}" './scripts/verify_openclaw_capability_truth.sh'
assert_file_contains "${DOC}" 'outbox/manual/'
assert_file_contains "${DOC}" 'status-triangulation-artifact'
assert_file_contains "${DOC}" 'WhatsApp sigue fuera y congelado'
assert_file_contains "${DOC}" 'runtime vivo sigue fuera'
assert_file_contains "${DOC}" 'browser nativo sigue fuera'

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"

echo "VERIFY_OK: openclaw status triangulation artifact pack checks passed"
