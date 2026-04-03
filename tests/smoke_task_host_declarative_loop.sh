#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Task Host Declarative Loop Smoke $$"
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

app_script="$tmpdir/task_host_loop_app.py"
cat >"$app_script" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${title}")
root.geometry("820x300+200+200")
root.configure(bg="#f4f4f4")

header = tk.Frame(root, bg="#324b5b", height=52)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Task host declarative loop smoke", fg="#ffffff", bg="#324b5b", font=("DejaVu Sans", 17, "bold")).pack(side="left", padx=18, pady=10)

body = tk.Frame(root, bg="#f4f4f4")
body.pack(fill="both", expand=True)
for line in [
    "A task should declare a host expectation",
    "Different host sources should feed one declarative evaluation loop",
    "The read-side should expose insufficient_evidence and match states canonically",
]:
    tk.Label(body, text=line, fg="#1c1c1c", bg="#f4f4f4", font=("DejaVu Sans", 14)).pack(anchor="w", padx=20, pady=8)

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

create_out="$(./scripts/task_create.sh "Smoke task host declarative loop" "Declare host expectation, refresh verification, and expose the result canonically" --type smoke-task-host-loop --owner system --source script)"
task_id="$(printf '%s\n' "$create_out" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_id" ] || {
  echo "FAIL: no task id extracted" >&2
  exit 1
}

./scripts/task_set_host_expectation.sh "$task_id" \
  --target-kind active-window \
  --require-summary \
  --min-artifact-count 1 \
  --note "Initial host expectation for declarative loop smoke." \
  --actor verify-task-host-loop >/dev/null

show_insufficient_path="$tmpdir/show-insufficient.json"
./scripts/task_panel_read.sh show "$task_id" >"$show_insufficient_path"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_refresh_host_verification.sh "$task_id" --source describe --refresh-host active-window --actor verify-task-host-loop >/dev/null

show_describe_match_path="$tmpdir/show-describe-match.json"
./scripts/task_panel_read.sh show "$task_id" >"$show_describe_match_path"
summary_describe_match_path="$tmpdir/task-summary-describe-match.txt"
./scripts/task_summary.sh "$task_id" >"$summary_describe_match_path"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_refresh_host_verification.sh "$task_id" --source perceive --actor verify-task-host-loop >/dev/null

show_perceive_match_path="$tmpdir/show-perceive-match.json"
summary_perceive_match_path="$tmpdir/task-summary-perceive-match.txt"
./scripts/task_panel_read.sh show "$task_id" >"$show_perceive_match_path"
./scripts/task_summary.sh "$task_id" >"$summary_perceive_match_path"

./scripts/task_set_host_expectation.sh "$task_id" \
  --target-kind active-window \
  --surface-category browser-web-app \
  --require-summary \
  --min-artifact-count 1 \
  --note "Require a surface_category that host_perceive does not project." \
  --actor verify-task-host-loop >/dev/null

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_refresh_host_verification.sh "$task_id" --source perceive --actor verify-task-host-loop >/dev/null

show_perceive_insufficient_path="$tmpdir/show-perceive-insufficient.json"
summary_perceive_insufficient_path="$tmpdir/task-summary-perceive-insufficient.txt"
./scripts/task_panel_read.sh show "$task_id" >"$show_perceive_insufficient_path"
./scripts/task_summary.sh "$task_id" >"$summary_perceive_insufficient_path"

python3 - "$task_id" "$show_insufficient_path" "$show_describe_match_path" "$show_perceive_match_path" "$show_perceive_insufficient_path" "$summary_describe_match_path" "$summary_perceive_match_path" "$summary_perceive_insufficient_path" "$cap_root" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
show_insufficient = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
show_describe_match = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
show_perceive_match = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
show_perceive_insufficient = json.loads(pathlib.Path(sys.argv[5]).read_text(encoding="utf-8"))
summary_describe_match = pathlib.Path(sys.argv[6]).read_text(encoding="utf-8")
summary_perceive_match = pathlib.Path(sys.argv[7]).read_text(encoding="utf-8")
summary_perceive_insufficient = pathlib.Path(sys.argv[8]).read_text(encoding="utf-8")
cap_root = pathlib.Path(sys.argv[9]).resolve()

task_a = show_insufficient["task"]
expectation_a = task_a["host_expectation"]
verification_a = task_a["host_verification"]
assert expectation_a["present"] is True, expectation_a
assert verification_a["present"] is True, verification_a
assert verification_a["status"] == "insufficient_evidence", verification_a
assert "no host evidence attached" in verification_a["reason"], verification_a

task_b = show_describe_match["task"]
host_b = task_b["host_evidence_summary"]
verification_b = task_b["host_verification"]
assert host_b["present"] is True, host_b
assert host_b["source_kind"] == "describe", host_b
assert host_b["capture_lane"] == "golem_host_describe", host_b
assert host_b["selection_policy"] == "latest_attached_then_source_precedence", host_b
assert verification_b["status"] == "match", verification_b
assert verification_b["source_kind"] == "describe", verification_b
assert verification_b["selection_policy"] == "latest_attached_then_source_precedence", verification_b
assert verification_b["last_evaluated_at"], verification_b
assert verification_b["stale"] is False, verification_b
assert verification_b["target_kind"] == "active-window", verification_b
assert pathlib.Path(verification_b["run_dir"]).resolve().is_relative_to(cap_root), verification_b
assert verification_b["artifact_count"] >= 6, verification_b
assert "host_expectation_present: yes" in summary_describe_match, summary_describe_match
assert "host_source_kind: describe" in summary_describe_match, summary_describe_match
assert "host_selection_policy: latest_attached_then_source_precedence" in summary_describe_match, summary_describe_match
assert "host_verification_status: match" in summary_describe_match, summary_describe_match
assert "host_verification_source_kind: describe" in summary_describe_match, summary_describe_match

task_c = show_perceive_match["task"]
host_c = task_c["host_evidence_summary"]
verification_c = task_c["host_verification"]
assert host_c["source_kind"] == "perceive", host_c
assert host_c["capture_lane"] == "golem_host_perceive", host_c
assert host_c["selection_policy"] == "latest_attached_then_source_precedence", host_c
assert verification_c["status"] == "match", verification_c
assert verification_c["source_kind"] == "perceive", verification_c
assert verification_c["selection_policy"] == "latest_attached_then_source_precedence", verification_c
assert verification_c["target_kind"] == "active-window", verification_c
assert pathlib.Path(verification_c["run_dir"]).resolve().is_relative_to(cap_root), verification_c
assert verification_c["artifact_count"] >= 5, verification_c
assert "host_source_kind: perceive" in summary_perceive_match, summary_perceive_match
assert "host_selection_policy: latest_attached_then_source_precedence" in summary_perceive_match, summary_perceive_match
assert "host_verification_status: match" in summary_perceive_match, summary_perceive_match
assert "host_verification_source_kind: perceive" in summary_perceive_match, summary_perceive_match

task_d = show_perceive_insufficient["task"]
expectation_d = task_d["host_expectation"]
verification_d = task_d["host_verification"]
assert expectation_d["surface_category"] == "browser-web-app", expectation_d
assert verification_d["status"] == "insufficient_evidence", verification_d
assert "missing host surface_category, expected browser-web-app" in verification_d["reason"], verification_d
assert verification_d["source_kind"] == "perceive", verification_d
assert verification_d["selection_policy"] == "latest_attached_then_source_precedence", verification_d
assert "host_verification_status: insufficient_evidence" in summary_perceive_insufficient, summary_perceive_insufficient
assert "host_source_kind: perceive" in summary_perceive_insufficient, summary_perceive_insufficient
assert "host_expectation_surface_category: browser-web-app" in summary_perceive_insufficient, summary_perceive_insufficient

print("SMOKE_TASK_HOST_DECLARATIVE_LOOP_OK")
print(f"TASK_HOST_LOOP_TASK {task_id}")
print(f"TASK_HOST_LOOP_INSUFFICIENT {verification_a['status']} {verification_a['reason']}")
print(f"TASK_HOST_LOOP_DESCRIBE_MATCH {verification_b['status']} {verification_b['source_kind']} {verification_b['artifact_count']}")
print(f"TASK_HOST_LOOP_PERCEIVE_MATCH {verification_c['status']} {verification_c['source_kind']} {verification_c['artifact_count']}")
print(f"TASK_HOST_LOOP_PERCEIVE_INSUFFICIENT {verification_d['status']} {verification_d['reason']}")
PY
