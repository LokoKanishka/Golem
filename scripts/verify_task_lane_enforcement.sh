#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

run_check() {
  local label="$1"
  shift

  printf '== %s ==\n' "$label"
  "$@"
  printf '\n'
}

run_check "task entrypoint policy" ./scripts/task_entrypoint_policy_check.sh
run_check "task cli minimal" ./scripts/verify_task_cli_minimal.sh
run_check "task git trace" ./scripts/task_git_trace_check.sh
run_check "task validate strict" ./scripts/task_validate.sh --all --strict
run_check "smoke task core" ./tests/smoke_task_core.sh

printf 'TASK_LANE_ENFORCEMENT_OK\n'
