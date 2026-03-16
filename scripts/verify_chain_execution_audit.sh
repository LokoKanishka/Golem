#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

extract_root_id() {
  local output="$1"
  local task_id
  task_id="$(printf '%s\n' "$output" | awk '/^TASK_CHAIN_(DELEGATED|OK|PLANNED) / {print $2}' | tail -n 1)"
  if [ -n "$task_id" ]; then
    printf '%s\n' "$task_id"
    return 0
  fi
  printf '%s\n' "$output" | awk '/^TASK_CREATED / {print $2}' | head -n 1 | xargs -r basename -s .json
}

cd "$REPO_ROOT"

run_output="$(./scripts/task_chain_run_v2.sh repo-analysis-worker-manual-multi "Verify chain execution audit" 2>&1 || true)"
printf '%s\n' "$run_output"

root_task_id="$(extract_root_id "$run_output")"
[ -n "$root_task_id" ] || fatal "no se pudo resolver root_task_id"
[ -f "$TASKS_DIR/${root_task_id}.json" ] || fatal "no existe la root creada: $root_task_id"

printf 'audit_root_id: %s\n' "$root_task_id"

set +e
incomplete_output="$(./scripts/task_chain_audit_execution.sh "$root_task_id" 2>&1)"
incomplete_exit="$?"
set -e
printf '%s\n' "$incomplete_output"

[ "$incomplete_exit" -eq 3 ] || fatal "el path incompleto debia salir WARN/3 y salio $incomplete_exit"
printf '%s\n' "$incomplete_output" | rg -q '^audit_status: WARN$' || fatal "faltó audit_status WARN en el path incompleto"
printf '%s\n' "$incomplete_output" | rg -q '^audit_reason: execution_incomplete$' || fatal "faltó audit_reason execution_incomplete"

mapfile -t worker_child_ids < <(
  python3 - "$TASKS_DIR/${root_task_id}.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for step in (task.get("chain_plan") or {}).get("steps") or []:
    if not step.get("await_worker_result"):
        continue
    child_task_id = str(step.get("child_task_id") or "").strip()
    if child_task_id:
        print(child_task_id)
PY
)

[ "${#worker_child_ids[@]}" -ge 2 ] || fatal "se esperaban al menos dos worker children awaitables"

set +e
settle_first_output="$(./scripts/task_chain_settle.sh "${worker_child_ids[0]}" done "Audit verify worker result 1" 2>&1)"
settle_first_exit="$?"
set -e
printf '%s\n' "$settle_first_output"
case "$settle_first_exit" in
  0|3) ;;
  *) fatal "el primer settlement devolvió $settle_first_exit" ;;
esac

set +e
settle_second_output="$(./scripts/task_chain_settle.sh "${worker_child_ids[1]}" done "Audit verify worker result 2" 2>&1)"
settle_second_exit="$?"
set -e
printf '%s\n' "$settle_second_output"
case "$settle_second_exit" in
  0|3) ;;
  *) fatal "el segundo settlement devolvió $settle_second_exit" ;;
esac

set +e
settle_root_output="$(./scripts/task_chain_settle.sh "$root_task_id" 2>&1)"
settle_root_exit="$?"
set -e
printf '%s\n' "$settle_root_output"
case "$settle_root_exit" in
  0|3) ;;
  *) fatal "el settlement final de la root devolvió $settle_root_exit" ;;
esac

set +e
coherent_output="$(./scripts/task_chain_audit_execution.sh "$root_task_id" --artifact 2>&1)"
coherent_exit="$?"
set -e
printf '%s\n' "$coherent_output"

[ "$coherent_exit" -eq 0 ] || fatal "el path coherente debia salir OK/0 y salio $coherent_exit"
printf '%s\n' "$coherent_output" | rg -q '^audit_status: OK$' || fatal "faltó audit_status OK en el path coherente"
printf '%s\n' "$coherent_output" | rg -q '^audit_reason: execution_coherent$' || fatal "faltó audit_reason execution_coherent"
printf '%s\n' "$coherent_output" | rg -q '^AUDIT_ARTIFACT ' || fatal "faltó AUDIT_ARTIFACT en el path coherente"

drift_fixture="$(mktemp "${TMPDIR:-/tmp}/golem-chain-audit-drift.XXXXXX.json")"
cleanup() {
  rm -f "$drift_fixture"
}
trap cleanup EXIT

python3 - "$TASKS_DIR/${root_task_id}.json" "$drift_fixture" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
task = json.loads(source.read_text(encoding="utf-8"))
task["effective_plan_sha256"] = "drifted-effective-plan-sha256"
target.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

set +e
drift_output="$(./scripts/task_chain_audit_execution.sh "$drift_fixture" 2>&1)"
drift_exit="$?"
set -e
printf '%s\n' "$drift_output"

[ "$drift_exit" -eq 1 ] || fatal "el path drift debia salir FAIL/1 y salio $drift_exit"
printf '%s\n' "$drift_output" | rg -q '^audit_status: FAIL$' || fatal "faltó audit_status FAIL en el path drift"
printf '%s\n' "$drift_output" | rg -q '^audit_reason: execution_drift$' || fatal "faltó audit_reason execution_drift"
printf '%s\n' "$drift_output" | rg -q 'effective_plan_sha256 no coincide' || fatal "faltó evidencia de hash drift"

printf 'VERIFY_CHAIN_EXECUTION_AUDIT_OK root=%s drift_fixture=%s\n' "$root_task_id" "$drift_fixture"
