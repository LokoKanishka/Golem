#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
list_out="$tmpdir/list.json"
summary_out="$tmpdir/summary.json"
show_out="$tmpdir/show.json"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

./scripts/task_panel_read.sh list --limit 20 >"$list_out"
./scripts/task_panel_read.sh summary >"$summary_out"

showable_task_id="$(python3 - "$list_out" "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys
import subprocess

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
repo_root = pathlib.Path(sys.argv[2])
tasks = data.get("tasks") or []

for task in tasks:
    task_id = task.get("id", "")
    if not task_id:
        continue
    result = subprocess.run(
        [str(repo_root / "scripts/task_panel_read.sh"), "show", task_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        print(task_id)
        break
PY
)"

if [[ -z "$showable_task_id" ]]; then
  echo "FAIL: panel list returned no stable task for show" >&2
  exit 1
fi

./scripts/task_panel_read.sh show "$showable_task_id" >"$show_out"

python3 - "$list_out" "$summary_out" "$show_out" <<'PY'
import json
import pathlib
import sys

list_payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
summary_payload = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
show_payload = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))

assert list_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert list_payload["meta"]["canonical_only"] is True
assert list_payload["meta"]["returned"] >= 1
assert list_payload["meta"]["matched"] >= list_payload["meta"]["returned"]
assert len(list_payload["tasks"]) >= 1

first_task = list_payload["tasks"][0]
assert first_task["id"].startswith("task-"), first_task
assert "status" in first_task and first_task["status"], first_task
assert "title" in first_task and first_task["title"], first_task
assert "host_evidence_present" in first_task, first_task
assert isinstance(first_task["host_evidence_present"], bool), first_task
assert "host_expectation_present" in first_task, first_task
assert isinstance(first_task["host_expectation_present"], bool), first_task
assert "host_verification_status" in first_task, first_task

assert summary_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert summary_payload["meta"]["canonical_only"] is True
inventory = summary_payload["inventory"]
assert inventory["total"] >= list_payload["meta"]["matched"], inventory
assert inventory["total"] >= 1000, inventory
assert isinstance(inventory["status_counts"], dict) and inventory["status_counts"], inventory
assert sum(inventory["status_counts"].values()) == inventory["total"], inventory
assert "host_evidence_tasks" in inventory, inventory
assert "host_expectation_tasks" in inventory, inventory
assert "host_verification_counts" in inventory, inventory

assert show_payload["meta"]["source_of_truth"] == "tasks/*.json"
assert show_payload["meta"]["canonical_only"] is True
task = show_payload["task"]
assert task["id"] == first_task["id"], (task["id"], first_task["id"])
assert task["task_id"] == task["id"], task
assert task["status"] == first_task["status"], (task["status"], first_task["status"])
assert "delivery" in task and isinstance(task["delivery"], dict), task
assert "history" in task and isinstance(task["history"], list) and task["history"], task
assert "host_evidence_summary" in task and isinstance(task["host_evidence_summary"], dict), task
assert "host_expectation" in task and isinstance(task["host_expectation"], dict), task
assert "host_verification" in task and isinstance(task["host_verification"], dict), task

print("SMOKE_PANEL_TASK_READ_OK")
print(f"PANEL_TASK_LIST_FIRST_ID {first_task['id']}")
print(f"PANEL_TASK_SUMMARY_TOTAL {inventory['total']}")
PY
