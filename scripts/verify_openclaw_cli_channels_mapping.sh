#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAPPING_DOC="${REPO_ROOT}/docs/OPENCLAW_CLI_CHANNELS_MAPPING.md"
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

[ -f "${MAPPING_DOC}" ] || fail "missing mapping doc: ${MAPPING_DOC}"
[ -f "${BASELINE_DOC}" ] || fail "missing baseline doc"
[ -f "${CURRENT_STATE_DOC}" ] || fail "missing current state doc"
[ -f "${HANDOFF_DOC}" ] || fail "missing handoff doc"

assert_file_contains "${MAPPING_DOC}" "## Proposito"
assert_file_contains "${MAPPING_DOC}" "## Relacion con la baseline pack"
assert_file_contains "${MAPPING_DOC}" "## Alcance"
assert_file_contains "${MAPPING_DOC}" "## Fuera de alcance"
assert_file_contains "${MAPPING_DOC}" "## Matriz operativa central"
assert_file_contains "${MAPPING_DOC}" "## Mapeo por familia"
assert_file_contains "${MAPPING_DOC}" "## Evidencia minima por familia"
assert_file_contains "${MAPPING_DOC}" "## Usos permitidos y no permitidos"
assert_file_contains "${MAPPING_DOC}" "## Como escribir futuros tickets usando este mapping"
assert_file_contains "${MAPPING_DOC}" "status"
assert_file_contains "${MAPPING_DOC}" "gateway"
assert_file_contains "${MAPPING_DOC}" "config"
assert_file_contains "${MAPPING_DOC}" "channels"
assert_file_contains "${MAPPING_DOC}" "docs/OPENCLAW_CLI_CHANNELS_BASELINE.md"
assert_file_contains "${MAPPING_DOC}" "docs/CURRENT_STATE.md"
assert_file_contains "${MAPPING_DOC}" "handoffs/HANDOFF_CURRENT.md"
assert_file_contains "${MAPPING_DOC}" "WhatsApp sigue congelado"
assert_file_contains "${MAPPING_DOC}" "browser nativo de OpenClaw sigue fuera"
assert_file_contains "${MAPPING_DOC}" "runtime vivo sigue fuera"

assert_file_contains "${CURRENT_STATE_DOC}" "docs/OPENCLAW_CLI_CHANNELS_MAPPING.md"
assert_file_contains "${HANDOFF_DOC}" "docs/OPENCLAW_CLI_CHANNELS_MAPPING.md"

echo "VERIFY_OK: openclaw cli + channels mapping checks passed"
