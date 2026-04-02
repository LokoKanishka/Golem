#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_DOC="${REPO_ROOT}/docs/OPENCLAW_CLI_CHANNELS_BASELINE.md"
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

[ -f "${BASELINE_DOC}" ] || fail "missing baseline doc: ${BASELINE_DOC}"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${BASELINE_DOC}" "## Proposito"
assert_file_contains "${BASELINE_DOC}" "## Alcance"
assert_file_contains "${BASELINE_DOC}" "## Fuera de alcance"
assert_file_contains "${BASELINE_DOC}" "## Superficies CLI clave"
assert_file_contains "${BASELINE_DOC}" "## Superficies Channels clave"
assert_file_contains "${BASELINE_DOC}" "## Matriz de utilidad y madurez"
assert_file_contains "${BASELINE_DOC}" "## Relacion con el estado real de Golem"
assert_file_contains "${BASELINE_DOC}" "## Como usar esta baseline para futuros tickets"
assert_file_contains "${BASELINE_DOC}" "WhatsApp sigue congelado"
assert_file_contains "${BASELINE_DOC}" "openclaw browser"
assert_file_contains "${BASELINE_DOC}" "browser sidecar"
assert_file_contains "${BASELINE_DOC}" "runtime vivo"
assert_file_contains "${BASELINE_DOC}" "channels"
assert_file_contains "${BASELINE_DOC}" "CLI"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_CLI_CHANNELS_BASELINE.md"
assert_file_contains "${CURRENT_STATE_DOC}" "WhatsApp sigue congelado"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_CLI_CHANNELS_BASELINE.md"
assert_file_contains "${HANDOFF_DOC}" "WhatsApp sigue congelado"

echo "VERIFY_OK: openclaw cli + channels baseline checks passed"
