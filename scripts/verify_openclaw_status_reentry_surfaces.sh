#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_verify() {
  local label="$1"
  local script_path="$2"

  echo "VERIFY_STEP: ${label}"
  "${script_path}"
}

echo "VERIFY_START: openclaw status reentry surfaces"
echo "VERIFY_NOTE: this composite verify covers only the read-side status reentry surface"
echo "VERIFY_NOTE: it does not prove delivery real, browser usable, readiness total, or permission to touch runtime"

run_verify "1/3 pre-closure index" "${ROOT}/scripts/verify_openclaw_status_pre_closure_index.sh"
run_verify "2/3 real closure index" "${ROOT}/scripts/verify_openclaw_status_real_closure_index.sh"
run_verify "3/3 reentry routes" "${ROOT}/scripts/verify_openclaw_status_reentry_routes.sh"

echo "VERIFY_OK: openclaw status reentry surfaces checks passed"
