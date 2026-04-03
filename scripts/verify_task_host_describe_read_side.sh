#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

printf 'TASK_HOST_READ_SIDE_NOTE: this verify covers only the canonical task read-side for attached host evidence\n'
printf 'TASK_HOST_READ_SIDE_NOTE: it does not prove delivery real, browser usable, readiness total, or permission to touch runtime\n\n'

printf '== shell syntax ==\n'
bash -n ./scripts/task_panel_read.sh
bash -n ./scripts/task_summary.sh
bash -n ./tests/smoke_task_host_describe_read_side.sh
printf '\n'

printf '== smoke host->task read side ==\n'
./tests/smoke_task_host_describe_read_side.sh
printf '\n'

printf 'VERIFY_TASK_HOST_DESCRIBE_READ_SIDE_OK\n'
