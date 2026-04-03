#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

printf 'TASK_HOST_LOOP_NOTE: this verify covers only the declarative task<->host expectation, evaluation, read-side, and refresh loop\n'
printf 'TASK_HOST_LOOP_NOTE: it does not prove delivery real, browser usable, readiness total, or permission to touch runtime\n\n'

printf '== shell syntax ==\n'
bash -n ./scripts/task_set_host_expectation.sh
bash -n ./scripts/task_evaluate_host_expectation.sh
bash -n ./scripts/task_refresh_host_verification.sh
bash -n ./tests/smoke_task_host_declarative_loop.sh
printf '\n'

printf '== smoke task<->host declarative loop ==\n'
./tests/smoke_task_host_declarative_loop.sh
printf '\n'

printf 'VERIFY_TASK_HOST_DECLARATIVE_LOOP_OK\n'
