#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md"
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

[ -f "${DOC}" ] || fail "missing snapshot workflow doc: ${DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"
[ -x "${HELPER}" ] || fail "missing executable helper: ${HELPER}"

assert_file_contains "${DOC}" "## Proposito"
assert_file_contains "${DOC}" "## Alcance"
assert_file_contains "${DOC}" "## Fuera de alcance"
assert_file_contains "${DOC}" "## Relacion con artifact pack, status evidence pack y status consistency pack"
assert_file_contains "${DOC}" "## Definicion del workflow minimo"
assert_file_contains "${DOC}" "## Casos canonicos de uso"
assert_file_contains "${DOC}" "### Caso 1: retome rapido"
assert_file_contains "${DOC}" "### Caso 2: verdad operativa corta"
assert_file_contains "${DOC}" "### Caso 3: consistencia documental read-side"
assert_file_contains "${DOC}" "## Inputs minimos por caso"
assert_file_contains "${DOC}" "## Outputs esperados por caso"
assert_file_contains "${DOC}" "## Convencion de invocacion minima de la helper"
assert_file_contains "${DOC}" "## Cuando usarlo"
assert_file_contains "${DOC}" "## Cuando no alcanza"
assert_file_contains "${DOC}" "## Tickets que si deberian usar este workflow"
assert_file_contains "${DOC}" "## Tickets que no deben apoyarse en este workflow"
assert_file_contains "${DOC}" "./scripts/render_status_triangulation_artifact.sh"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_EVIDENCE_PACK.md"
assert_file_contains "${DOC}" "docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md"
assert_file_contains "${DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${DOC}" "outbox/manual/"
assert_file_contains "${DOC}" "quick-reentry"
assert_file_contains "${DOC}" "state-check"
assert_file_contains "${DOC}" "consistency-doc"
assert_file_contains "${DOC}" "WhatsApp sigue fuera y congelado"
assert_file_contains "${DOC}" "runtime vivo sigue fuera"
assert_file_contains "${DOC}" "browser nativo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md"

echo "VERIFY_OK: openclaw status triangulation snapshot workflow checks passed"
