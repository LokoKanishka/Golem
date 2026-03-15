#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

LAST_OUTPUT=""
LAST_EXIT_CODE=0
PARTIAL_ROOT_ID=""
PARTIAL_CHILD_A=""
PARTIAL_CHILD_B=""
PARTIAL_FINAL_ARTIFACT=""
BLOCKED_ROOT_ID=""
BLOCKED_CHILD_A=""
BLOCKED_CHILD_B=""

fail() {
  printf 'VERIFY_MULTI_WORKER_AWAIT_FAIL %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  local label="$1"
  local cmd="$2"
  local output
  local exit_code

  printf '\n## %s\n' "$label"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf 'exit_code: %s\n' "$exit_code"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

assert_exit_in() {
  local exit_code="$1"
  shift
  local expected
  for expected in "$@"; do
    if [ "$exit_code" = "$expected" ]; then
      return 0
    fi
  done
  fail "exit_code inesperado: $exit_code (esperaba uno de: $*)"
}

extract_chain_root_id() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^TASK_CHAIN_(PLANNED|DELEGATED|OK|FAIL|BLOCKED) / {print $2}' | tail -n 1
}

awaiting_worker_child_ids() {
  local root_task_id="$1"
  python3 - "$TASKS_DIR/${root_task_id}.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
steps = ((task.get("chain_plan") or {}).get("steps") or [])
children = []
for step in sorted(steps, key=lambda value: (int(value.get("step_order", 0) or 0), value.get("step_name", ""))):
    if not step.get("await_worker_result"):
        continue
    child_task_id = str(step.get("child_task_id", "")).strip()
    if child_task_id:
        children.append(child_task_id)
for child_task_id in children:
    print(child_task_id)
PY
}

task_json_value() {
  local task_id="$1"
  local expression="$2"
  python3 - "$TASKS_DIR/${task_id}.json" "$expression" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expression = sys.argv[2]

if expression == "status":
    print(task.get("status", ""))
elif expression == "chain_status":
    print(task.get("chain_status", ""))
elif expression == "final_artifact_path":
    print((task.get("chain_summary") or {}).get("final_artifact_path", ""))
elif expression == "awaiting_worker_result_steps":
    print((task.get("chain_summary") or {}).get("awaiting_worker_result_steps", ""))
elif expression == "resolved_worker_result_steps":
    print((task.get("chain_summary") or {}).get("resolved_worker_result_steps", ""))
elif expression == "worker_child_ids":
    for item in (task.get("chain_summary") or {}).get("worker_child_ids", []):
        print(item)
elif expression == "awaiting_worker_child_ids":
    for item in (task.get("chain_summary") or {}).get("awaiting_worker_child_ids", []):
        print(item)
elif expression == "resolved_worker_child_ids":
    for item in (task.get("chain_summary") or {}).get("resolved_worker_child_ids", []):
        print(item)
elif expression.startswith("dependency_barrier_status:"):
    barrier_name = expression.split(":", 1)[1]
    for barrier in (task.get("chain_summary") or {}).get("dependency_barriers", []):
        if barrier.get("group_name") == barrier_name:
            print(barrier.get("status", ""))
            raise SystemExit(0)
    print("")
elif expression.startswith("step_status:"):
    step_name = expression.split(":", 1)[1]
    for step in ((task.get("chain_plan") or {}).get("steps") or []):
        if step.get("step_name") == step_name:
            print(step.get("status", ""))
            raise SystemExit(0)
    print("")
elif expression == "worker_result_status":
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            print(output.get("status", ""))
            raise SystemExit(0)
    print("")
else:
    raise SystemExit(f"unsupported expression: {expression}")
PY
}

create_result_packet() {
  local child_task_id="$1"
  local root_task_id="$2"
  local result_status="$3"
  local summary="$4"
  local packet_path="$5"
  local handoff_packet_rel="handoffs/${child_task_id}.packet.json"

  mkdir -p "$(dirname "$packet_path")"

  python3 - "$REPO_ROOT" "$handoff_packet_rel" "$child_task_id" "$root_task_id" "$result_status" "$summary" "$packet_path" <<'PY'
import datetime
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
handoff_packet_path = (repo_root / sys.argv[2]).resolve()
child_task_id = sys.argv[3]
root_task_id = sys.argv[4]
result_status = sys.argv[5]
summary = sys.argv[6]
packet_path = pathlib.Path(sys.argv[7]).resolve()

handoff_packet = json.loads(handoff_packet_path.read_text(encoding="utf-8"))
generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

packet = {
    "packet_kind": "worker_result_packet",
    "packet_version": "1.0",
    "generated_at": generated_at,
    "child_task_id": child_task_id,
    "root_task_id": root_task_id,
    "worker_name": "verify-multi-worker-await-roundtrip",
    "source": "verify_multi_worker_await_roundtrip",
    "result_status": result_status,
    "summary": summary,
    "notes": [
        "generated by scripts/verify_multi_worker_await_roundtrip.sh",
        f"derived_from_handoff_packet={sys.argv[2]}",
    ],
    "artifact_paths": [],
    "commit_info": {},
    "evidence": {
        "handoff_packet_path": sys.argv[2],
        "handoff_packet_version": handoff_packet.get("packet_version", ""),
        "worker_target": handoff_packet.get("worker_target", ""),
    },
}

packet_path.write_text(json.dumps(packet, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY
}

assert_partial_state() {
  local root_task_id="$1"
  local child_a="$2"
  local child_b="$3"

  [ "$(task_json_value "$root_task_id" status)" = "delegated" ] || fail "partial path: root no quedo delegated"
  [ "$(task_json_value "$root_task_id" chain_status)" = "awaiting_worker_result" ] || fail "partial path: chain_status inesperado"
  [ "$(task_json_value "$root_task_id" awaiting_worker_result_steps)" = "1" ] || fail "partial path: awaiting count inesperado"
  [ "$(task_json_value "$root_task_id" resolved_worker_result_steps)" = "1" ] || fail "partial path: resolved count inesperado"
  [ "$(task_json_value "$child_a" status)" = "done" ] || fail "partial path: child_a no quedo done"
  [ "$(task_json_value "$child_a" worker_result_status)" = "done" ] || fail "partial path: worker_result child_a inesperado"
  [ "$(task_json_value "$child_b" status)" = "delegated" ] || fail "partial path: child_b no sigue delegated"
  [ "$(task_json_value "$root_task_id" step_status:local-summarize-architecture)" = "done" ] || fail "partial path: local barrier parcial no corrio"
  [ "$(task_json_value "$root_task_id" step_status:local-compare-multi-worker-docs)" = "planned" ] || fail "partial path: continuation no quedo planned"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:architecture-ready)" = "satisfied" ] || fail "partial path: architecture-ready no quedo satisfied"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:analysis-workers)" = "waiting" ] || fail "partial path: analysis-workers no quedo waiting"
}

assert_success_state() {
  local root_task_id="$1"
  local child_a="$2"
  local child_b="$3"

  [ "$(task_json_value "$root_task_id" status)" = "done" ] || fail "success path: root no termino done"
  case "$(task_json_value "$root_task_id" chain_status)" in
    completed|completed_with_warnings) ;;
    *) fail "success path: chain_status inesperado" ;;
  esac
  [ "$(task_json_value "$root_task_id" awaiting_worker_result_steps)" = "0" ] || fail "success path: awaiting count inesperado"
  [ "$(task_json_value "$root_task_id" resolved_worker_result_steps)" = "2" ] || fail "success path: resolved count inesperado"
  [ "$(task_json_value "$child_a" status)" = "done" ] || fail "success path: child_a no termino done"
  [ "$(task_json_value "$child_b" status)" = "done" ] || fail "success path: child_b no termino done"
  [ "$(task_json_value "$root_task_id" step_status:local-summarize-architecture)" = "done" ] || fail "success path: barrier parcial local no termino done"
  [ "$(task_json_value "$root_task_id" step_status:local-compare-multi-worker-docs)" = "done" ] || fail "success path: continuation local no termino done"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:architecture-ready)" = "satisfied" ] || fail "success path: architecture-ready no quedo satisfied"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:analysis-workers)" = "satisfied" ] || fail "success path: analysis-workers no quedo satisfied"
}

assert_blocked_state() {
  local root_task_id="$1"
  local child_a="$2"
  local child_b="$3"

  [ "$(task_json_value "$root_task_id" status)" = "blocked" ] || fail "blocked path: root no termino blocked"
  [ "$(task_json_value "$root_task_id" chain_status)" = "blocked" ] || fail "blocked path: chain_status inesperado"
  [ "$(task_json_value "$root_task_id" awaiting_worker_result_steps)" = "0" ] || fail "blocked path: awaiting count inesperado"
  [ "$(task_json_value "$root_task_id" resolved_worker_result_steps)" = "2" ] || fail "blocked path: resolved count inesperado"
  [ "$(task_json_value "$child_a" status)" = "done" ] || fail "blocked path: child_a no quedo done"
  [ "$(task_json_value "$child_a" worker_result_status)" = "done" ] || fail "blocked path: worker_result child_a inesperado"
  [ "$(task_json_value "$child_b" status)" = "blocked" ] || fail "blocked path: child_b no termino blocked"
  [ "$(task_json_value "$child_b" worker_result_status)" = "blocked" ] || fail "blocked path: worker_result child_b inesperado"
  [ "$(task_json_value "$root_task_id" step_status:local-summarize-architecture)" = "done" ] || fail "blocked path: barrier parcial local no corrio"
  [ "$(task_json_value "$root_task_id" step_status:local-compare-multi-worker-docs)" = "skipped" ] || fail "blocked path: continuation local no quedo skipped"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:architecture-ready)" = "satisfied" ] || fail "blocked path: architecture-ready no quedo satisfied"
  [ "$(task_json_value "$root_task_id" dependency_barrier_status:analysis-workers)" = "blocked" ] || fail "blocked path: analysis-workers no quedo blocked"
}

print_case_summary() {
  local label="$1"
  local root_task_id="$2"
  local child_a="$3"
  local child_b="$4"

  printf '\n### %s Summary\n' "$label"
  printf 'root_task_id: %s\n' "$root_task_id"
  printf 'worker_child_id: %s\n' "$child_a"
  printf 'worker_child_id: %s\n' "$child_b"
  printf 'root_status: %s\n' "$(task_json_value "$root_task_id" status)"
  printf 'chain_status: %s\n' "$(task_json_value "$root_task_id" chain_status)"
  printf 'awaiting_worker_result_steps: %s\n' "$(task_json_value "$root_task_id" awaiting_worker_result_steps)"
  printf 'resolved_worker_result_steps: %s\n' "$(task_json_value "$root_task_id" resolved_worker_result_steps)"
  printf 'architecture_barrier_status: %s\n' "$(task_json_value "$root_task_id" dependency_barrier_status:architecture-ready)"
  printf 'analysis_barrier_status: %s\n' "$(task_json_value "$root_task_id" dependency_barrier_status:analysis-workers)"
  printf 'partial_continuation_status: %s\n' "$(task_json_value "$root_task_id" step_status:local-summarize-architecture)"
  printf 'full_continuation_status: %s\n' "$(task_json_value "$root_task_id" step_status:local-compare-multi-worker-docs)"
}

mkdir -p "$OUTBOX_DIR"

printf '# Multi Worker Await Roundtrip Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Start Multi Await Manual Chain" "./scripts/task_chain_run_v2.sh repo-analysis-worker-manual-multi \"Multi worker await partial+success path\""
assert_exit_in "$LAST_EXIT_CODE" 3
PARTIAL_ROOT_ID="$(extract_chain_root_id "$LAST_OUTPUT")"
[ -n "$PARTIAL_ROOT_ID" ] || fail "no se pudo extraer root_task_id del path parcial"
mapfile -t partial_children < <(awaiting_worker_child_ids "$PARTIAL_ROOT_ID")
[ "${#partial_children[@]}" -eq 2 ] || fail "se esperaban 2 worker children awaitables para el path parcial"
PARTIAL_CHILD_A="${partial_children[0]}"
PARTIAL_CHILD_B="${partial_children[1]}"

packet_a="$OUTBOX_DIR/partial-${PARTIAL_CHILD_A}.worker-result.json"
create_result_packet "$PARTIAL_CHILD_A" "$PARTIAL_ROOT_ID" "done" "First worker resolved while the second one still waits" "$packet_a"
run_cmd "Import First Worker Result And Settle" "./scripts/task_import_worker_result.sh ${packet_a#$REPO_ROOT/} --settle"
assert_exit_in "$LAST_EXIT_CODE" 3
assert_partial_state "$PARTIAL_ROOT_ID" "$PARTIAL_CHILD_A" "$PARTIAL_CHILD_B"
run_cmd "Reconcile Partial Root" "./scripts/task_chain_reconcile_pending.sh $PARTIAL_ROOT_ID"
assert_exit_in "$LAST_EXIT_CODE" 0

packet_b="$OUTBOX_DIR/complete-${PARTIAL_CHILD_B}.worker-result.json"
create_result_packet "$PARTIAL_CHILD_B" "$PARTIAL_ROOT_ID" "done" "Second worker resolved and allowed final continuation" "$packet_b"
run_cmd "Import Second Worker Result And Settle" "./scripts/task_import_worker_result.sh ${packet_b#$REPO_ROOT/} --settle"
assert_exit_in "$LAST_EXIT_CODE" 0
assert_success_state "$PARTIAL_ROOT_ID" "$PARTIAL_CHILD_A" "$PARTIAL_CHILD_B"
PARTIAL_FINAL_ARTIFACT="$(task_json_value "$PARTIAL_ROOT_ID" final_artifact_path)"
[ -n "$PARTIAL_FINAL_ARTIFACT" ] || fail "success path: root sin final_artifact_path"
run_cmd "Validate Success Final Artifact" "./scripts/validate_markdown_artifact.sh $PARTIAL_FINAL_ARTIFACT"
assert_exit_in "$LAST_EXIT_CODE" 0
print_case_summary "Partial Then Complete" "$PARTIAL_ROOT_ID" "$PARTIAL_CHILD_A" "$PARTIAL_CHILD_B"

run_cmd "Start Multi Await Blocked Chain" "./scripts/task_chain_run_v2.sh repo-analysis-worker-manual-multi \"Multi worker await blocked path\""
assert_exit_in "$LAST_EXIT_CODE" 3
BLOCKED_ROOT_ID="$(extract_chain_root_id "$LAST_OUTPUT")"
[ -n "$BLOCKED_ROOT_ID" ] || fail "no se pudo extraer root_task_id del path blocked"
mapfile -t blocked_children < <(awaiting_worker_child_ids "$BLOCKED_ROOT_ID")
[ "${#blocked_children[@]}" -eq 2 ] || fail "se esperaban 2 worker children awaitables para el path blocked"
BLOCKED_CHILD_A="${blocked_children[0]}"
BLOCKED_CHILD_B="${blocked_children[1]}"

blocked_packet="$OUTBOX_DIR/blocked-${BLOCKED_CHILD_A}.worker-result.json"
create_result_packet "$BLOCKED_CHILD_A" "$BLOCKED_ROOT_ID" "done" "Architecture worker resolved before the full-analysis barrier closed" "$blocked_packet"
run_cmd "Import First Blocked-Path Worker Result And Settle" "./scripts/task_import_worker_result.sh ${blocked_packet#$REPO_ROOT/} --settle"
assert_exit_in "$LAST_EXIT_CODE" 3
partial_blocked_packet="$OUTBOX_DIR/blocked-${BLOCKED_CHILD_B}.worker-result.json"
create_result_packet "$BLOCKED_CHILD_B" "$BLOCKED_ROOT_ID" "blocked" "Critical verification worker blocked after the architecture-only barrier had already opened" "$partial_blocked_packet"
run_cmd "Import Blocked Worker Result And Settle" "./scripts/task_import_worker_result.sh ${partial_blocked_packet#$REPO_ROOT/} --settle"
assert_exit_in "$LAST_EXIT_CODE" 2
assert_blocked_state "$BLOCKED_ROOT_ID" "$BLOCKED_CHILD_A" "$BLOCKED_CHILD_B"
print_case_summary "Blocked After Partial Barrier Success" "$BLOCKED_ROOT_ID" "$BLOCKED_CHILD_A" "$BLOCKED_CHILD_B"

printf '\n## Final Summary\n'
printf 'path | root_task_id | root_status | chain_status | awaiting_worker_result_steps | resolved_worker_result_steps\n'
printf 'partial_then_complete | %s | %s | %s | %s | %s\n' \
  "$PARTIAL_ROOT_ID" \
  "$(task_json_value "$PARTIAL_ROOT_ID" status)" \
  "$(task_json_value "$PARTIAL_ROOT_ID" chain_status)" \
  "$(task_json_value "$PARTIAL_ROOT_ID" awaiting_worker_result_steps)" \
  "$(task_json_value "$PARTIAL_ROOT_ID" resolved_worker_result_steps)"
printf 'blocked_after_partial_barrier | %s | %s | %s | %s | %s\n' \
  "$BLOCKED_ROOT_ID" \
  "$(task_json_value "$BLOCKED_ROOT_ID" status)" \
  "$(task_json_value "$BLOCKED_ROOT_ID" chain_status)" \
  "$(task_json_value "$BLOCKED_ROOT_ID" awaiting_worker_result_steps)" \
  "$(task_json_value "$BLOCKED_ROOT_ID" resolved_worker_result_steps)"

printf '\nVERIFY_MULTI_WORKER_AWAIT_OK partial_root=%s blocked_root=%s\n' "$PARTIAL_ROOT_ID" "$BLOCKED_ROOT_ID"
