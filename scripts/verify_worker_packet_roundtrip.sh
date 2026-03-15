#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

LAST_OUTPUT=""
LAST_EXIT_CODE=0
SUCCESS_ROOT_ID=""
SUCCESS_CHILD_ID=""
SUCCESS_PACKET_PATH=""
SUCCESS_FINAL_ARTIFACT=""
BLOCKED_ROOT_ID=""
BLOCKED_CHILD_ID=""
BLOCKED_PACKET_PATH=""
BLOCKED_FINAL_ARTIFACT=""

fail() {
  printf 'VERIFY_WORKER_PACKET_ROUNDTRIP_FAIL %s\n' "$*" >&2
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
  printf '%s\n' "$output" | awk '/^TASK_CHAIN_(OK|DONE|DELEGATED|BLOCKED|FAILED) / {print $2}' | tail -n 1
}

awaiting_worker_child_id() {
  local root_task_id="$1"
  python3 - "$TASKS_DIR/${root_task_id}.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
steps = ((task.get("chain_plan") or {}).get("steps") or [])
for step in steps:
    if step.get("await_worker_result"):
        print(step.get("child_task_id", ""))
        raise SystemExit(0)
raise SystemExit(1)
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
elif expression == "worker_result_status":
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            print(output.get("status", ""))
            raise SystemExit(0)
    print("")
elif expression == "continuation_status":
    steps = ((task.get("chain_plan") or {}).get("steps") or [])
    await_step = None
    for step in steps:
        if step.get("await_worker_result"):
            await_step = step
            break
    if await_step is not None:
        await_order = int(await_step.get("step_order", 0) or 0)
        continuation_steps = [
            step
            for step in steps
            if int(step.get("step_order", 0) or 0) > await_order
        ]
        if continuation_steps:
            continuation = sorted(
                continuation_steps,
                key=lambda step: (int(step.get("step_order", 0) or 0), step.get("step_name", "")),
            )[0]
            print(continuation.get("status", ""))
            raise SystemExit(0)
    print("")
elif expression == "continuation_name":
    steps = ((task.get("chain_plan") or {}).get("steps") or [])
    await_step = None
    for step in steps:
        if step.get("await_worker_result"):
            await_step = step
            break
    if await_step is not None:
        await_order = int(await_step.get("step_order", 0) or 0)
        continuation_steps = [
            step
            for step in steps
            if int(step.get("step_order", 0) or 0) > await_order
        ]
        if continuation_steps:
            continuation = sorted(
                continuation_steps,
                key=lambda step: (int(step.get("step_order", 0) or 0), step.get("step_name", "")),
            )[0]
            print(continuation.get("step_name", ""))
            raise SystemExit(0)
    print("")
elif expression == "worker_step_status":
    steps = ((task.get("chain_plan") or {}).get("steps") or [])
    for step in steps:
        if step.get("await_worker_result"):
            print(step.get("status", ""))
            raise SystemExit(0)
    print("")
else:
    raise SystemExit(f"unsupported expression: {expression}")
PY
}

assert_file() {
  local rel_path="$1"
  [ -f "$REPO_ROOT/$rel_path" ] || fail "falta archivo esperado: $rel_path"
}

assert_contains() {
  local needle="$1"
  local rel_path="$2"
  grep -Fq "$needle" "$REPO_ROOT/$rel_path" || fail "no se encontro referencia '$needle' en $rel_path"
}

create_result_packet() {
  local child_task_id="$1"
  local root_task_id="$2"
  local result_status="$3"
  local summary="$4"
  local packet_path="$5"
  local handoff_packet_rel="handoffs/${child_task_id}.packet.json"
  local packet_dir

  packet_dir="$(dirname "$packet_path")"
  mkdir -p "$packet_dir"

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
    "worker_name": "verify-worker-packet-roundtrip",
    "source": "verify_worker_packet_roundtrip",
    "result_status": result_status,
    "summary": summary,
    "notes": [
        "generated by scripts/verify_worker_packet_roundtrip.sh",
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

assert_success_path() {
  local root_task_id="$1"
  local child_task_id="$2"

  local root_status
  local chain_status
  local child_status
  local worker_result_status
  local continuation_status
  local worker_step_status

  root_status="$(task_json_value "$root_task_id" status)"
  chain_status="$(task_json_value "$root_task_id" chain_status)"
  child_status="$(task_json_value "$child_task_id" status)"
  worker_result_status="$(task_json_value "$child_task_id" worker_result_status)"
  continuation_status="$(task_json_value "$root_task_id" continuation_status)"
  worker_step_status="$(task_json_value "$root_task_id" worker_step_status)"

  [ "$root_status" = "done" ] || fail "success path: root no termino done ($root_status)"
  case "$chain_status" in
    done|completed_with_warnings) ;;
    *) fail "success path: chain_status inesperado ($chain_status)" ;;
  esac
  [ "$child_status" = "done" ] || fail "success path: child worker no termino done ($child_status)"
  [ "$worker_result_status" = "done" ] || fail "success path: worker_result_status inesperado ($worker_result_status)"
  [ "$worker_step_status" = "done" ] || fail "success path: worker step no termino done ($worker_step_status)"
  [ "$continuation_status" = "done" ] || fail "success path: continuation local no termino done ($continuation_status)"
}

assert_blocked_path() {
  local root_task_id="$1"
  local child_task_id="$2"

  local root_status
  local chain_status
  local child_status
  local worker_result_status
  local continuation_status
  local worker_step_status

  root_status="$(task_json_value "$root_task_id" status)"
  chain_status="$(task_json_value "$root_task_id" chain_status)"
  child_status="$(task_json_value "$child_task_id" status)"
  worker_result_status="$(task_json_value "$child_task_id" worker_result_status)"
  continuation_status="$(task_json_value "$root_task_id" continuation_status)"
  worker_step_status="$(task_json_value "$root_task_id" worker_step_status)"

  [ "$root_status" = "blocked" ] || fail "blocked path: root no termino blocked ($root_status)"
  [ "$chain_status" = "blocked" ] || fail "blocked path: chain_status inesperado ($chain_status)"
  [ "$child_status" = "blocked" ] || fail "blocked path: child worker no termino blocked ($child_status)"
  [ "$worker_result_status" = "blocked" ] || fail "blocked path: worker_result_status inesperado ($worker_result_status)"
  [ "$worker_step_status" = "blocked" ] || fail "blocked path: worker step no termino blocked ($worker_step_status)"
  [ "$continuation_status" = "skipped" ] || fail "blocked path: continuation local no quedo skipped ($continuation_status)"
}

print_case_summary() {
  local label="$1"
  local root_task_id="$2"
  local child_task_id="$3"
  local result_packet_path="$4"
  local final_artifact_path="$5"

  printf '\n### %s Summary\n' "$label"
  printf 'root_task_id: %s\n' "$root_task_id"
  printf 'worker_child_id: %s\n' "$child_task_id"
  printf 'root_status: %s\n' "$(task_json_value "$root_task_id" status)"
  printf 'chain_status: %s\n' "$(task_json_value "$root_task_id" chain_status)"
  printf 'worker_status: %s\n' "$(task_json_value "$child_task_id" status)"
  printf 'worker_result_status: %s\n' "$(task_json_value "$child_task_id" worker_result_status)"
  printf 'worker_step_status: %s\n' "$(task_json_value "$root_task_id" worker_step_status)"
  printf 'continuation_step_name: %s\n' "$(task_json_value "$root_task_id" continuation_name)"
  printf 'continuation_status: %s\n' "$(task_json_value "$root_task_id" continuation_status)"
  printf 'handoff_markdown: %s\n' "handoffs/${child_task_id}.md"
  printf 'codex_ticket: %s\n' "handoffs/${child_task_id}.codex.md"
  printf 'handoff_packet: %s\n' "handoffs/${child_task_id}.packet.json"
  printf 'result_packet: %s\n' "${result_packet_path#$REPO_ROOT/}"
  if [ -n "$final_artifact_path" ]; then
    printf 'final_artifact: %s\n' "$final_artifact_path"
  fi
}

verify_roundtrip_case() {
  local label="$1"
  local result_status="$2"
  local summary="$3"
  local prefix="$4"
  local root_task_id=""
  local child_task_id=""
  local result_packet_path=""
  local final_artifact_path=""

  run_cmd "${label}: Start Manual Worker Chain" "./scripts/task_chain_run_v2.sh repo-analysis-worker-manual \"$label\""
  assert_exit_in "$LAST_EXIT_CODE" 3
  root_task_id="$(extract_chain_root_id "$LAST_OUTPUT")"
  [ -n "$root_task_id" ] || fail "$label: no se pudo extraer root_task_id"

  child_task_id="$(awaiting_worker_child_id "$root_task_id")" || fail "$label: no se pudo resolver worker child awaitable"
  [ -n "$child_task_id" ] || fail "$label: worker child vacia"

  assert_file "handoffs/${child_task_id}.md"
  assert_file "handoffs/${child_task_id}.codex.md"
  assert_file "handoffs/${child_task_id}.packet.json"
  assert_contains "handoffs/${child_task_id}.packet.json" "handoffs/${child_task_id}.md"
  assert_contains "handoffs/${child_task_id}.packet.json" "handoffs/${child_task_id}.codex.md"

  run_cmd "${label}: Root Status Before Import" "./scripts/task_chain_status.sh $root_task_id"
  run_cmd "${label}: Worker Child Before Import" "./scripts/task_show.sh $child_task_id"

  result_packet_path="$OUTBOX_DIR/${prefix}-${child_task_id}.worker-result.json"
  create_result_packet "$child_task_id" "$root_task_id" "$result_status" "$summary" "$result_packet_path"
  [ -f "$result_packet_path" ] || fail "$label: no se pudo crear result packet"

  run_cmd "${label}: Import Result Packet And Settle" "./scripts/task_import_worker_result.sh ${result_packet_path#$REPO_ROOT/} --settle"
  if [ "$result_status" = "done" ]; then
    assert_exit_in "$LAST_EXIT_CODE" 0
  else
    assert_exit_in "$LAST_EXIT_CODE" 0 2
  fi

  run_cmd "${label}: Root Status After Import" "./scripts/task_chain_status.sh $root_task_id"
  run_cmd "${label}: Root Summary After Import" "./scripts/task_chain_summary.sh $root_task_id"
  run_cmd "${label}: Worker Child After Import" "./scripts/task_show.sh $child_task_id"

  if [ "$result_status" = "done" ]; then
    assert_success_path "$root_task_id" "$child_task_id"
  else
    assert_blocked_path "$root_task_id" "$child_task_id"
  fi

  final_artifact_path="$(task_json_value "$root_task_id" final_artifact_path)"
  [ -n "$final_artifact_path" ] || fail "$label: root sin final_artifact_path"
  run_cmd "${label}: Validate Final Artifact" "./scripts/validate_markdown_artifact.sh $final_artifact_path"
  assert_exit_in "$LAST_EXIT_CODE" 0

  print_case_summary "$label" "$root_task_id" "$child_task_id" "$result_packet_path" "$final_artifact_path"

  case "$prefix" in
    success)
      SUCCESS_ROOT_ID="$root_task_id"
      SUCCESS_CHILD_ID="$child_task_id"
      SUCCESS_PACKET_PATH="$result_packet_path"
      SUCCESS_FINAL_ARTIFACT="$final_artifact_path"
      ;;
    blocked)
      BLOCKED_ROOT_ID="$root_task_id"
      BLOCKED_CHILD_ID="$child_task_id"
      BLOCKED_PACKET_PATH="$result_packet_path"
      BLOCKED_FINAL_ARTIFACT="$final_artifact_path"
      ;;
    *)
      fail "prefix inesperado: $prefix"
      ;;
  esac
}

mkdir -p "$OUTBOX_DIR"

printf '# Worker Packet Roundtrip Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

verify_roundtrip_case \
  "Worker packet roundtrip success path" \
  "done" \
  "Verify roundtrip success path imported result and resumed the root" \
  "success"

verify_roundtrip_case \
  "Worker packet roundtrip blocked path" \
  "blocked" \
  "Verify roundtrip blocked path imported result and kept the root blocked" \
  "blocked"

printf '\n## Final Summary\n'
printf 'path | root_task_id | worker_child_id | root_status | chain_status | worker_status | continuation_status\n'
printf 'success | %s | %s | %s | %s | %s | %s\n' \
  "$SUCCESS_ROOT_ID" \
  "$SUCCESS_CHILD_ID" \
  "$(task_json_value "$SUCCESS_ROOT_ID" status)" \
  "$(task_json_value "$SUCCESS_ROOT_ID" chain_status)" \
  "$(task_json_value "$SUCCESS_CHILD_ID" status)" \
  "$(task_json_value "$SUCCESS_ROOT_ID" continuation_status)"
printf 'blocked | %s | %s | %s | %s | %s | %s\n' \
  "$BLOCKED_ROOT_ID" \
  "$BLOCKED_CHILD_ID" \
  "$(task_json_value "$BLOCKED_ROOT_ID" status)" \
  "$(task_json_value "$BLOCKED_ROOT_ID" chain_status)" \
  "$(task_json_value "$BLOCKED_CHILD_ID" status)" \
  "$(task_json_value "$BLOCKED_ROOT_ID" continuation_status)"

printf '\nVERIFY_WORKER_PACKET_ROUNDTRIP_OK success_root=%s blocked_root=%s\n' "$SUCCESS_ROOT_ID" "$BLOCKED_ROOT_ID"
