#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

type_output="$(./scripts/delegation_decide.sh type repo-analysis)"
printf '%s\n' "$type_output"

created_output="$(./scripts/task_new.sh repo-analysis "Delegation repo-analysis verify test")"
printf '%s\n' "$created_output"

task_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_path" ] || {
  echo "ERROR: no se pudo extraer task_path" >&2
  exit 1
}
task_id="$(basename "$task_path" .json)"

task_output="$(./scripts/delegation_decide.sh task "$task_id")"
printf '%s\n' "$task_output"

TYPE_OUTPUT="$type_output" TASK_OUTPUT="$task_output" python3 - <<'PY'
import os

expected = {
    "owner": "worker_future",
    "task_type": "repo-analysis",
}

for env_name in ("TYPE_OUTPUT", "TASK_OUTPUT"):
    values = {}
    for line in os.environ[env_name].splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
    for key, expected_value in expected.items():
        assert values.get(key) == expected_value, (env_name, key, values)
    assert values.get("rationale"), (env_name, "missing rationale", values)
    assert values.get("escalation"), (env_name, "missing escalation", values)
PY

printf 'VERIFY_DELEGATION_DECISION_OK %s\n' "$task_id"
