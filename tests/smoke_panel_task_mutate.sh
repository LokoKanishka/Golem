#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
create_out="$tmpdir/create.json"
update_out="$tmpdir/update.json"
close_out="$tmpdir/close.json"
host_expect_out="$tmpdir/host-expect.json"
host_refresh_out="$tmpdir/host-refresh.json"
task_id=""

cleanup() {
  rm -rf "$tmpdir"
  if [[ -n "$task_id" && -f "$TASKS_DIR/$task_id.json" ]]; then
    rm -f "$TASKS_DIR/$task_id.json"
  fi
}
trap cleanup EXIT

./scripts/task_panel_mutate.sh create \
  --title "Smoke panel task mutate" \
  --objective "Smoke panel task mutate objective" \
  --type smoke-panel-task-mutate \
  --owner system \
  --accept "panel mutate smoke create" \
  --canonical-session smoke-panel-task-mutate \
  >"$create_out"

task_id="$(python3 - "$create_out" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload["task"]["id"])
PY
)"

[[ -n "$task_id" ]] || {
  echo "FAIL: no task id from panel create" >&2
  exit 1
}

./scripts/task_panel_mutate.sh update "$task_id" \
  --status running \
  --owner panel-operator \
  --title "Smoke panel task mutate updated" \
  --objective "Smoke panel task mutate updated objective" \
  --append-accept "panel mutate smoke update" \
  --note "panel update applied" \
  >"$update_out"

./scripts/task_panel_mutate.sh set-host-expectation "$task_id" \
  --target-kind active-window \
  --require-summary \
  --min-artifact-count 1 \
  --note "panel host expectation applied" \
  >"$host_expect_out"

./scripts/task_panel_mutate.sh refresh-host-verification "$task_id" \
  --actor panel \
  >"$host_refresh_out"

./scripts/task_panel_mutate.sh close "$task_id" \
  --status done \
  --note "panel close applied" \
  --owner panel-operator \
  >"$close_out"

python3 - "$create_out" "$update_out" "$host_expect_out" "$host_refresh_out" "$close_out" "$TASKS_DIR/$task_id.json" <<'PY'
import json
import pathlib
import sys

create_payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
update_payload = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
host_expect_payload = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
host_refresh_payload = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
close_payload = json.loads(pathlib.Path(sys.argv[5]).read_text(encoding="utf-8"))
task = json.loads(pathlib.Path(sys.argv[6]).read_text(encoding="utf-8"))

assert create_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert create_payload["meta"]["canonical_only"] is True
assert "task_create.sh" in create_payload["meta"]["canonical_script_command"]
assert create_payload["task"]["status"] == "todo", create_payload["task"]
assert create_payload["task"]["source_channel"] == "panel", create_payload["task"]
assert create_payload["task"]["task_id"] == create_payload["task"]["id"], create_payload["task"]

assert update_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert "task_update.sh" in update_payload["meta"]["canonical_script_command"]
assert update_payload["task"]["status"] == "running", update_payload["task"]
assert update_payload["task"]["owner"] == "panel-operator", update_payload["task"]
assert update_payload["task"]["title"] == "Smoke panel task mutate updated", update_payload["task"]
assert update_payload["task"]["objective"] == "Smoke panel task mutate updated objective", update_payload["task"]
assert "panel mutate smoke update" in update_payload["task"]["acceptance_criteria"], update_payload["task"]

assert host_expect_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert "task_set_host_expectation.sh" in host_expect_payload["meta"]["canonical_script_command"]
assert host_expect_payload["task"]["host_expectation"]["present"] is True, host_expect_payload["task"]
assert host_expect_payload["task"]["host_expectation"]["target_kind"] == "active-window", host_expect_payload["task"]
assert host_expect_payload["task"]["host_verification"]["status"] == "insufficient_evidence", host_expect_payload["task"]

assert host_refresh_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert "task_refresh_host_verification.sh" in host_refresh_payload["meta"]["canonical_script_command"]
assert host_refresh_payload["task"]["host_verification"]["present"] is True, host_refresh_payload["task"]
assert host_refresh_payload["task"]["host_verification"]["status"] == "insufficient_evidence", host_refresh_payload["task"]
assert "no host evidence attached" in host_refresh_payload["task"]["host_verification"]["reason"], host_refresh_payload["task"]

assert close_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert "task_close.sh" in close_payload["meta"]["canonical_script_command"]
assert close_payload["task"]["status"] == "done", close_payload["task"]
assert close_payload["task"]["closure_note"] == "panel close applied", close_payload["task"]

assert task["status"] == "done", task["status"]
assert task["source_channel"] == "panel", task["source_channel"]
assert task["owner"] == "panel-operator", task["owner"]
assert task["closure_note"] == "panel close applied", task["closure_note"]
assert task["host_expectation"]["target_kind"] == "active-window", task["host_expectation"]
assert task["host_verification"]["status"] == "insufficient_evidence", task["host_verification"]
assert task["notes"][-3:] == ["panel update applied", "panel host expectation applied", "panel close applied"], task["notes"]
assert task["acceptance_criteria"][-1] == "panel mutate smoke update", task["acceptance_criteria"]
assert task["history"][0]["action"] == "created", task["history"][0]
assert task["history"][-3]["action"] == "host_expectation_set", task["history"][-3]
assert task["history"][-2]["action"] == "host_expectation_evaluated", task["history"][-2]
assert task["history"][-1]["action"] == "closed_done", task["history"][-1]

print("SMOKE_PANEL_TASK_MUTATE_OK")
print(f"PANEL_TASK_MUTATE_ID {task['id']}")
print(f"PANEL_TASK_MUTATE_FINAL_STATUS {task['status']}")
print(f"PANEL_TASK_MUTATE_HOST_VERIFICATION {task['host_verification']['status']}")
PY
