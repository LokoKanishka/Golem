#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Task Host Describe Read Side Smoke $$"
task_id=""
dialog_pid=""
window_id=""

cleanup() {
  if [[ -n "$window_id" ]]; then
    wmctrl -i -c "$window_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$dialog_pid" ]] && kill -0 "$dialog_pid" 2>/dev/null; then
    kill "$dialog_pid" 2>/dev/null || true
    wait "$dialog_pid" 2>/dev/null || true
  fi
  if [[ -n "$task_id" && -f "$REPO_ROOT/tasks/$task_id.json" ]]; then
    rm -f "$REPO_ROOT/tasks/$task_id.json"
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

wait_for_active_title() {
  local expected="$1"
  local active_title=""
  for _ in $(seq 1 50); do
    active_title="$(xdotool getactivewindow getwindowname 2>/dev/null || true)"
    if [[ "$active_title" == "$expected" ]]; then
      return 0
    fi
    wmctrl -a "$expected" >/dev/null 2>&1 || true
    sleep 0.1
  done
  printf 'FAIL: active window did not settle on expected title: %s (last=%s)\n' "$expected" "$active_title" >&2
  return 1
}

app_script="$tmpdir/task_host_read_side_app.py"
cat >"$app_script" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${title}")
root.geometry("780x280+180+180")
root.configure(bg="#f7f7f7")

header = tk.Frame(root, bg="#29404f", height=52)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Host evidence should be readable from task lane", fg="#ffffff", bg="#29404f", font=("DejaVu Sans", 17, "bold")).pack(side="left", padx=18, pady=10)

body = tk.Frame(root, bg="#f7f7f7")
body.pack(fill="both", expand=True)
for line in [
    "The bridge already writes host evidence canonically",
    "This smoke checks that task read-side now recognizes it",
    "No parallel viewer should be needed to locate host evidence",
]:
    tk.Label(body, text=line, fg="#1f1f1f", bg="#f7f7f7", font=("DejaVu Sans", 14)).pack(anchor="w", padx=20, pady=8)

root.after(30000, root.destroy)
root.mainloop()
PY

python3 "$app_script" >"$tmpdir/app.log" 2>&1 &
dialog_pid="$!"

for _ in $(seq 1 100); do
  window_id="$(xdotool search --name "$title" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$window_id" ]]; then
    break
  fi
  sleep 0.1
done

[[ -n "$window_id" ]] || {
  cat "$tmpdir/app.log" >&2 || true
  echo "FAIL: window with title containing \"$title\" was not found within 10s" >&2
  exit 1
}

xdotool windowactivate "$window_id" >/dev/null 2>&1 || wmctrl -ia "$window_id" >/dev/null 2>&1 || true
wait_for_active_title "$title"

create_out="$(./scripts/task_create.sh "Smoke host describe read-side" "Expose host evidence canonically through task read surfaces" --type smoke-host-task-read-side --owner system --source script)"
task_id="$(printf '%s\n' "$create_out" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_id" ] || {
  echo "FAIL: no task id extracted" >&2
  exit 1
}

summary_before="$(./scripts/task_panel_read.sh summary)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_attach_host_describe_evidence.sh "$task_id" active-window --actor verify-task-host-read-side >/dev/null

show_json_path="$tmpdir/show.json"
list_json_path="$tmpdir/list.json"
summary_before_path="$tmpdir/summary-before.json"
summary_after_path="$tmpdir/summary-after.json"
human_summary_path="$tmpdir/task-summary.txt"

printf '%s\n' "$summary_before" >"$summary_before_path"
./scripts/task_panel_read.sh show "$task_id" >"$show_json_path"
./scripts/task_panel_read.sh list --status todo >"$list_json_path"
./scripts/task_panel_read.sh summary >"$summary_after_path"
./scripts/task_summary.sh "$task_id" >"$human_summary_path"

python3 - "$task_id" "$show_json_path" "$list_json_path" "$summary_before_path" "$summary_after_path" "$human_summary_path" "$cap_root" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
show_payload = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
list_payload = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
summary_before = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
summary_after = json.loads(pathlib.Path(sys.argv[5]).read_text(encoding="utf-8"))
human_summary = pathlib.Path(sys.argv[6]).read_text(encoding="utf-8")
cap_root = pathlib.Path(sys.argv[7]).resolve()

task = show_payload["task"]
host = task["host_evidence_summary"]

assert host["present"] is True, host
assert host["source"] == "host", host
assert host["capture_lane"] == "golem_host_describe", host
assert host["target_kind"] == "active-window", host
assert host["last_attached_at"], host
assert host["summary"], host
assert host["evidence_path"], host
assert host["run_dir"], host
assert pathlib.Path(host["run_dir"]).resolve().is_relative_to(cap_root), host["run_dir"]
assert host["artifact_count"] >= 6, host
assert len(host["artifact_references"]) == host["artifact_count"], host
assert isinstance(host["non_empty_structured_fields"], list), host
assert isinstance(host["non_empty_fine_fields"], list), host
assert isinstance(host["non_empty_contextual_refinements"], list), host
assert isinstance(host["non_empty_surface_state_fields"], list), host

list_task = next((entry for entry in list_payload["tasks"] if entry["id"] == task_id), None)
assert list_task is not None, list_payload["tasks"][:3]
assert list_task["host_evidence_present"] is True, list_task
assert list_task["host_surface_category"] == host["surface_category"], (list_task, host)
assert list_task["host_surface_confidence"] == host["surface_confidence"], (list_task, host)
assert list_task["host_last_attached_at"] == host["last_attached_at"], (list_task, host)

before_count = summary_before["inventory"].get("host_evidence_tasks", 0)
after_count = summary_after["inventory"].get("host_evidence_tasks", 0)
assert after_count >= before_count + 1, (before_count, after_count)

assert "host_evidence_present: yes" in human_summary, human_summary
assert "host_capture_lane: golem_host_describe" in human_summary, human_summary
assert "host_target_kind: active-window" in human_summary, human_summary
assert "host_artifact_count: " in human_summary, human_summary
assert "host_summary: " in human_summary, human_summary

print("SMOKE_TASK_HOST_DESCRIBE_READ_SIDE_OK")
print(f"TASK_HOST_READ_SIDE_TASK {task_id}")
print(f"TASK_HOST_READ_SIDE_LAST_ATTACHED_AT {host['last_attached_at']}")
print(f"TASK_HOST_READ_SIDE_SURFACE {host['surface_category']}:{host['surface_confidence']}")
print(f"TASK_HOST_READ_SIDE_ARTIFACT_COUNT {host['artifact_count']}")
print(f"TASK_HOST_READ_SIDE_SUMMARY_HOST_TASKS {after_count}")
PY
