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
    "The latest attached host evidence should be evaluated canonically",
    "The read-side should expose insufficient_evidence, match and mismatch states",
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
  --min-surface-confidence uncertain \
  --require-summary \
  --min-artifact-count 1 \
  --note "Initial host expectation for declarative loop smoke." \
  --actor verify-task-host-loop >/dev/null

show_insufficient_path="$tmpdir/show-insufficient.json"
./scripts/task_panel_read.sh show "$task_id" >"$show_insufficient_path"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/task_refresh_host_verification.sh "$task_id" --refresh-host active-window --actor verify-task-host-loop >/dev/null

show_match_path="$tmpdir/show-match.json"
./scripts/task_panel_read.sh show "$task_id" >"$show_match_path"
summary_match_path="$tmpdir/task-summary-match.txt"
./scripts/task_summary.sh "$task_id" >"$summary_match_path"

./scripts/task_set_host_expectation.sh "$task_id" \
  --target-kind active-window \
  --surface-category browser-web-app \
  --min-surface-confidence uncertain \
  --require-summary \
  --min-artifact-count 1 \
  --note "Force a mismatch against the same host evidence." \
  --actor verify-task-host-loop >/dev/null

./scripts/task_refresh_host_verification.sh "$task_id" --actor verify-task-host-loop >/dev/null

show_mismatch_path="$tmpdir/show-mismatch.json"
summary_mismatch_path="$tmpdir/task-summary-mismatch.txt"
./scripts/task_panel_read.sh show "$task_id" >"$show_mismatch_path"
./scripts/task_summary.sh "$task_id" >"$summary_mismatch_path"

python3 - "$task_id" "$show_insufficient_path" "$show_match_path" "$show_mismatch_path" "$summary_match_path" "$summary_mismatch_path" "$cap_root" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
show_insufficient = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
show_match = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
show_mismatch = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
summary_match = pathlib.Path(sys.argv[5]).read_text(encoding="utf-8")
summary_mismatch = pathlib.Path(sys.argv[6]).read_text(encoding="utf-8")
cap_root = pathlib.Path(sys.argv[7]).resolve()

task_a = show_insufficient["task"]
expectation_a = task_a["host_expectation"]
verification_a = task_a["host_verification"]
assert expectation_a["present"] is True, expectation_a
assert verification_a["present"] is True, verification_a
assert verification_a["status"] == "insufficient_evidence", verification_a
assert "no host evidence attached" in verification_a["reason"], verification_a

task_b = show_match["task"]
host_b = task_b["host_evidence_summary"]
verification_b = task_b["host_verification"]
assert host_b["present"] is True, host_b
assert verification_b["status"] == "match", verification_b
assert verification_b["last_evaluated_at"], verification_b
assert verification_b["stale"] is False, verification_b
assert verification_b["target_kind"] == "active-window", verification_b
assert pathlib.Path(verification_b["run_dir"]).resolve().is_relative_to(cap_root), verification_b
assert verification_b["artifact_count"] >= 6, verification_b
assert "host_expectation_present: yes" in summary_match, summary_match
assert "host_verification_status: match" in summary_match, summary_match

task_c = show_mismatch["task"]
expectation_c = task_c["host_expectation"]
verification_c = task_c["host_verification"]
assert expectation_c["surface_category"] == "browser-web-app", expectation_c
assert verification_c["status"] == "mismatch", verification_c
assert "surface_category expected browser-web-app got" in verification_c["reason"], verification_c
assert "host_verification_status: mismatch" in summary_mismatch, summary_mismatch
assert "host_expectation_surface_category: browser-web-app" in summary_mismatch, summary_mismatch

print("SMOKE_TASK_HOST_DECLARATIVE_LOOP_OK")
print(f"TASK_HOST_LOOP_TASK {task_id}")
print(f"TASK_HOST_LOOP_INSUFFICIENT {verification_a['status']} {verification_a['reason']}")
print(f"TASK_HOST_LOOP_MATCH {verification_b['status']} {verification_b['target_kind']} {verification_b['artifact_count']}")
print(f"TASK_HOST_LOOP_MISMATCH {verification_c['status']} {verification_c['reason']}")
PY
