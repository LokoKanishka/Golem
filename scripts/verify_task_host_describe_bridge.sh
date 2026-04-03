#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

printf 'TASK_HOST_DESCRIBE_BRIDGE_NOTE: this verify covers only the canonical host->task evidence bridge\n'
printf 'TASK_HOST_DESCRIBE_BRIDGE_NOTE: it does not prove delivery real, browser usable, readiness total, or permission to touch runtime\n\n'

printf '== shell syntax ==\n'
bash -n ./scripts/task_attach_host_describe_evidence.sh
bash -n ./tests/smoke_task_host_describe_evidence.sh
printf '\n'

printf '== smoke host->task describe evidence ==\n'
./tests/smoke_task_host_describe_evidence.sh
printf '\n'

printf 'VERIFY_TASK_HOST_DESCRIBE_BRIDGE_OK\n'
