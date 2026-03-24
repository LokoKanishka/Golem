#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Firefox - Golem Visual Reading Smoke $$ [synthetic]"
app_pid=""
window_id=""

wait_for_active_title() {
  local expected="$1"
  local active_title=""
  local attempt=0
  for _ in $(seq 1 50); do
    attempt=$((attempt + 1))
    active_title="$(xdotool getactivewindow getwindowname 2>/dev/null || true)"
    if [[ "$active_title" == "$expected" ]]; then
      return 0
    fi
    if (( attempt % 10 == 0 )); then
      wmctrl -a "$expected" >/dev/null 2>&1 || true
    fi
    sleep 0.1
  done
  printf 'FAIL: active window did not settle on expected title: %s (last=%s)\n' "$expected" "$active_title" >&2
  return 1
}

cleanup() {
  if [[ -n "$window_id" ]]; then
    wmctrl -i -c "$window_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

app_script="$tmpdir/visual_layout_app.py"
cat >"$app_script" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${title}")
root.geometry("980x720+80+80")
root.configure(bg="#f4f4f4")

header = tk.Frame(root, bg="#22313f", height=70)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(
    header,
    text="Visual Reading Smoke",
    fg="white",
    bg="#22313f",
    font=("DejaVu Sans", 24, "bold"),
).pack(side="left", padx=24, pady=18)
tk.Label(
    header,
    text="Header Summary",
    fg="#d8dee9",
    bg="#22313f",
    font=("DejaVu Sans", 14),
).pack(side="right", padx=24)

body = tk.Frame(root, bg="#f4f4f4")
body.pack(fill="both", expand=True)

sidebar = tk.Frame(body, bg="#dbe7f3", width=240)
sidebar.pack(side="left", fill="y")
tk.Label(sidebar, text="Sidebar Notes", bg="#dbe7f3", font=("DejaVu Sans", 18, "bold")).pack(anchor="w", padx=16, pady=(18, 8))
for line in ["Alpha queue", "Beta status", "Gamma followup", "Delta evidence"]:
    tk.Label(sidebar, text=line, bg="#dbe7f3", font=("DejaVu Sans", 14)).pack(anchor="w", padx=20, pady=4)

main = tk.Frame(body, bg="white")
main.pack(side="left", fill="both", expand=True, padx=(16, 16), pady=16)
tk.Label(main, text="Main Content", bg="white", font=("DejaVu Sans", 22, "bold")).pack(anchor="w", padx=18, pady=(18, 8))
text = tk.Text(main, wrap="word", font=("DejaVu Sans Mono", 14), height=16, width=56)
text.pack(fill="both", expand=True, padx=18, pady=(0, 18))
text.insert(
    "1.0",
    "Structured review window\n"
    "Operator summary line\n"
    "Visible text should be readable\n"
    "Layout evidence must stay explicit\n"
    "Main panel contains denser content than sidebar\n"
    "Footer actions remain separate\n"
    "Open Report is the primary action\n"
    "Details is secondary\n",
)
text.configure(state="disabled")

footer = tk.Frame(root, bg="#eef2f5", height=72)
footer.pack(fill="x")
footer.pack_propagate(False)
tk.Label(footer, text="Footer Actions", bg="#eef2f5", font=("DejaVu Sans", 18, "bold")).pack(side="left", padx=20, pady=18)
tk.Label(footer, text="Open Report", bg="#eef2f5", font=("DejaVu Sans", 16, "bold")).pack(side="left", padx=18)
tk.Label(footer, text="Details", bg="#eef2f5", font=("DejaVu Sans", 16)).pack(side="left", padx=18)

root.after(30000, root.destroy)
root.mainloop()
PY

python3 "$app_script" >"$tmpdir/visual-layout-app.log" 2>&1 &
app_pid="$!"

wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$title" --timeout 10 --json
)"

window_id="$(python3 - "$wait_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
print(payload["window"]["window_id"])
PY
)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh focus --title "$title" --json >/dev/null
wait_for_active_title "$title"

active_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh active-window --json
)"

desktop_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh desktop --json
)"

python3 - "$active_json" "$desktop_json" "$title" <<'PY'
import json
import pathlib
import sys

active_payload = json.loads(sys.argv[1])
desktop_payload = json.loads(sys.argv[2])
title = sys.argv[3]

assert active_payload["target"]["kind"] == "active-window", active_payload["target"]
assert desktop_payload["target"]["kind"] == "desktop", desktop_payload["target"]

active_description = active_payload["description"]
layout = active_description["layout"]
roles = {section["role"] for section in layout["sections"]}
surface_classification = active_description["surface_classification"]
useful_lines = active_description["useful_lines"]
useful_regions = active_description["useful_regions"]
structured_fields = active_description["structured_fields"]
fine_fields = structured_fields["fine_fields"]
contextual_refinements = structured_fields["contextual_refinements"]

assert title in active_description["target_window"]["title"], active_description["target_window"]
assert {"header", "left_sidebar", "main_content"}.issubset(roles), layout
assert surface_classification["category"] == "browser-web-app", surface_classification
assert useful_lines, useful_lines
assert useful_regions, useful_regions
assert structured_fields["category"] == "browser-web-app", structured_fields
assert structured_fields["fields"]["page_title_candidates"], structured_fields
assert structured_fields["fields"]["header_text"], structured_fields
assert structured_fields["fields"]["primary_content_snippets"], structured_fields
assert fine_fields["primary_header_candidate"], fine_fields
assert fine_fields["page_title_candidate"], fine_fields
assert fine_fields["main_content_snippets"], fine_fields
assert fine_fields["primary_cta_candidate"], fine_fields
assert contextual_refinements["primary_header_candidate"], contextual_refinements
assert contextual_refinements["primary_cta_candidate"], contextual_refinements
assert contextual_refinements["secondary_action_candidates"], contextual_refinements
assert contextual_refinements["main_content_snippets"], contextual_refinements
assert contextual_refinements["primary_cta_candidate"][0]["priority"] == "primary", contextual_refinements
assert contextual_refinements["secondary_action_candidates"][0]["priority"] == "secondary", contextual_refinements
assert "Details" in json.dumps(contextual_refinements["secondary_action_candidates"]), contextual_refinements
normalized_ocr_text = pathlib.Path(active_payload["artifacts"]["ocr_normalized_text"]).read_text(encoding="utf-8")
assert "Visual Reading Smoke" in normalized_ocr_text or "Yisual Reading Smoke" in normalized_ocr_text
assert "Sidebar Notes" in normalized_ocr_text
assert "Main Content" in normalized_ocr_text

claims_text = "\n".join(claim["text"] for claim in active_description["claims"])
assert "layout heuristics suggest" in claims_text.lower(), claims_text
assert "surface classification heuristics read the visible target as" in claims_text.lower(), claims_text
assert "prioritized visible cues include" in claims_text.lower(), claims_text
assert "layout_heuristics" in json.dumps(active_payload["description"]["source_breakdown"]), active_payload["description"]["source_breakdown"]
assert "surface_classification_heuristics" in json.dumps(active_payload["description"]["source_breakdown"]), active_payload["description"]["source_breakdown"]
assert "structured_fields_heuristics" in json.dumps(active_payload["description"]["source_breakdown"]), active_payload["description"]["source_breakdown"]
assert "contextual_refinement_heuristics" in json.dumps(active_payload["description"]["source_breakdown"]), active_payload["description"]["source_breakdown"]

for key in ("ocr_text", "ocr_enhanced_text", "ocr_normalized_text", "layout", "surface_profile", "structured_fields", "description", "sources"):
    path = pathlib.Path(active_payload["artifacts"][key])
    assert path.exists(), path
    assert path.stat().st_size > 0, path

desktop_claims = "\n".join(claim["text"] for claim in desktop_payload["description"]["claims"])
assert "metadata" in desktop_claims.lower(), desktop_claims
assert "surface classification heuristics read the visible target as" in desktop_claims.lower(), desktop_claims

print("SMOKE_HOST_DESCRIBE_VISUAL_READING_OK")
print(f"HOST_DESCRIBE_VISUAL_LAYOUT_ROLES {sorted(roles)}")
print(f"HOST_DESCRIBE_VISUAL_SURFACE {surface_classification['category']}:{surface_classification['confidence']}")
print(f"HOST_DESCRIBE_VISUAL_ACTIVE_SUMMARY {active_description['summary']}")
print(f"HOST_DESCRIBE_VISUAL_DESKTOP_RUN_DIR {desktop_payload['run_dir']}")
PY
