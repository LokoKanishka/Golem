#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Task Host Describe Bridge Smoke $$"
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

app_script="$tmpdir/task_host_bridge_app.py"
cat >"$app_script" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${title}")
root.geometry("760x260+140+140")
root.configure(bg="#f2f2f2")

header = tk.Frame(root, bg="#203040", height=50)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Host -> task bridge smoke", fg="#ffffff", bg="#203040", font=("DejaVu Sans", 18, "bold")).pack(side="left", padx=18, pady=10)

body = tk.Frame(root, bg="#f2f2f2")
body.pack(fill="both", expand=True)
for line in [
    "Perception must stay audited",
    "The task lane must remain canonical",
    "This smoke proves host evidence can enter a task",
]:
    tk.Label(body, text=line, fg="#202020", bg="#f2f2f2", font=("DejaVu Sans", 14)).pack(anchor="w", padx=20, pady=8)

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

create_out="$(./scripts/task_create.sh "Smoke host describe bridge" "Attach audited host describe evidence into a canonical task" --type smoke-host-task-bridge --owner system --source script)"
task_id="$(printf '%s\n' "$create_out" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_id" ] || {
  echo "FAIL: no task id extracted" >&2
  exit 1
}

bridge_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_attach_host_describe_evidence.sh "$task_id" active-window --actor verify-task-host-bridge --json
)"

panel_json="$(./scripts/task_panel_read.sh show "$task_id")"

python3 - "$bridge_json" "$panel_json" "$cap_root" "$title" <<'PY'
import json
import pathlib
import sys

bridge = json.loads(sys.argv[1])
panel = json.loads(sys.argv[2])
cap_root = pathlib.Path(sys.argv[3]).resolve()
title = sys.argv[4]

assert bridge["meta"]["bridge"] == "task_attach_host_describe_evidence", bridge["meta"]
assert bridge["meta"]["source_of_truth"] == "tasks/*.json", bridge["meta"]
assert bridge["meta"]["canonical_only"] is True, bridge["meta"]
assert bridge["meta"]["host_capture_lane"] == "golem_host_describe", bridge["meta"]

result = bridge["meta"]["result"]
assert result["source"] == "host", result
assert result["capture_lane"] == "golem_host_describe", result
assert result["target_kind"] == "active-window", result
assert result["run_dir"], result
assert pathlib.Path(result["run_dir"]).resolve().is_relative_to(cap_root), result["run_dir"]
assert result["surface_category"], result
assert result["surface_confidence"], result
assert result["summary"], result
assert isinstance(result["non_empty_structured_fields"], list), result
assert isinstance(result["non_empty_fine_fields"], list), result
assert isinstance(result["non_empty_contextual_refinements"], list), result
assert isinstance(result["non_empty_surface_state_fields"], list), result

task = bridge["task"]
assert panel["task"]["id"] == task["id"], (panel["task"]["id"], task["id"])

evidence = task["evidence"][-1]
assert evidence["type"] == "host-describe", evidence
assert "source=host" in evidence["note"], evidence
assert evidence["command"].endswith("--json"), evidence["command"]
evidence_result = json.loads(evidence["result"])
assert evidence_result["source"] == "host", evidence_result
assert evidence_result["target_kind"] == "active-window", evidence_result

artifacts = bridge["meta"]["attached_artifacts"]
assert len(artifacts) >= 6, artifacts
for artifact in artifacts:
    artifact_path = pathlib.Path(artifact)
    if not artifact_path.is_absolute():
        artifact_path = pathlib.Path.cwd() / artifact_path
    assert artifact_path.exists(), artifact_path

artifact_set = set(task["artifacts"])
for artifact in artifacts:
    assert artifact in artifact_set, (artifact, task["artifacts"])

outputs = [entry for entry in task.get("outputs", []) if entry.get("kind") == "host-describe-evidence"]
assert outputs, task.get("outputs", [])
assert outputs[-1]["exit_code"] == 0, outputs[-1]
assert "TASK_HOST_DESCRIBE_EVIDENCE_ATTACHED" in outputs[-1]["content"], outputs[-1]
assert outputs[-1]["source"] == "host", outputs[-1]
assert outputs[-1]["bridge"] == "task_attach_host_describe_evidence", outputs[-1]

history_actions = [entry["action"] for entry in task.get("history", [])]
assert "evidence_added" in history_actions, history_actions
assert "artifact_added" in history_actions, history_actions

description_artifact = next(a for a in artifacts if a.endswith("description.json"))
description_path = pathlib.Path(description_artifact)
if not description_path.is_absolute():
    description_path = pathlib.Path.cwd() / description_path
description = json.loads(description_path.read_text(encoding="utf-8"))
assert title in description["target_window"]["title"], description["target_window"]

print("SMOKE_TASK_HOST_DESCRIBE_EVIDENCE_OK")
print(f"TASK_HOST_DESCRIBE_BRIDGE_TASK {task['id']}")
print(f"TASK_HOST_DESCRIBE_BRIDGE_RUN_DIR {result['run_dir']}")
print(f"TASK_HOST_DESCRIBE_BRIDGE_SURFACE {result['surface_category']}:{result['surface_confidence']}")
print(
    "TASK_HOST_DESCRIBE_BRIDGE_FIELD_COUNTS "
    f"structured={len(result['non_empty_structured_fields'])} "
    f"fine={len(result['non_empty_fine_fields'])} "
    f"contextual={len(result['non_empty_contextual_refinements'])} "
    f"bundle={len(result['non_empty_surface_state_fields'])}"
)
PY
