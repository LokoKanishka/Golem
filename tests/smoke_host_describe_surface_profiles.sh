#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
editor_title="Visual Studio Code - Golem Editor Surface Smoke $$ [synthetic]"
chat_title="ChatGPT - Golem Chat Surface Smoke $$ [synthetic]"
terminal_title="Golem Terminal Surface Smoke $$ [synthetic]"
browser_title="Firefox - Golem Browser Surface Smoke $$ [synthetic]"
editor_pid=""
chat_pid=""
terminal_pid=""
browser_pid=""

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
  for pid in "$editor_pid" "$chat_pid" "$terminal_pid" "$browser_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$tmpdir"
}
trap cleanup EXIT

editor_app="$tmpdir/editor_surface_app.py"
cat >"$editor_app" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${editor_title}")
root.geometry("1080x760+80+80")
root.configure(bg="#1e1e1e")

header = tk.Frame(root, bg="#252526", height=52)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="workspace/golem/scripts/golem_host_describe_analyze.py", fg="#d4d4d4", bg="#252526", font=("DejaVu Sans", 14, "bold")).pack(side="left", padx=16, pady=12)
tk.Label(header, text="Problems 1", fg="#f48771", bg="#252526", font=("DejaVu Sans", 12)).pack(side="right", padx=16)

tabs = tk.Frame(root, bg="#2d2d30", height=40)
tabs.pack(fill="x")
tabs.pack_propagate(False)
for text_value, color, style in [
    ("golem_host_describe_analyze.py", "#ffffff", "bold"),
    ("smoke_host_describe_surface_profiles.sh", "#c8c8c8", "normal"),
    ("HOST_CAPABILITIES.md", "#c8c8c8", "normal"),
]:
    tk.Label(tabs, text=text_value, fg=color, bg="#2d2d30", font=("DejaVu Sans", 12, style)).pack(side="left", padx=14, pady=10)

body = tk.Frame(root, bg="#1e1e1e")
body.pack(fill="both", expand=True)

sidebar = tk.Frame(body, bg="#252526", width=250)
sidebar.pack(side="left", fill="y")
sidebar.pack_propagate(False)
tk.Label(sidebar, text="EXPLORER", fg="#cccccc", bg="#252526", font=("DejaVu Sans", 15, "bold")).pack(anchor="w", padx=16, pady=(18, 10))
for line in ["golem", "scripts", "tests", "docs", "golem_host_describe_analyze.py"]:
    tk.Label(sidebar, text=line, fg="#d4d4d4", bg="#252526", font=("DejaVu Sans", 13)).pack(anchor="w", padx=22, pady=4)

main = tk.Frame(body, bg="#1e1e1e")
main.pack(side="left", fill="both", expand=True)
text = tk.Text(main, wrap="none", font=("DejaVu Sans Mono", 14), bg="#1e1e1e", fg="#d4d4d4", insertbackground="#d4d4d4")
text.pack(fill="both", expand=True, padx=18, pady=18)
text.insert(
    "1.0",
    "def classify_surface_profile(app, title, process, props, lines, layout):\\n"
    "    if \\"Traceback\\" in joined_text:\\n"
    "        return \\"editor\\"\\n"
    "    return \\"unknown\\"\\n\\n"
    "import json\\n"
    "Traceback sample line\\n"
    "error: active_tab_candidate mismatch\\n"
    "warning: stale tab ordering\\n"
    "workspace/golem/tests/smoke_host_describe_surface_profiles.sh\\n"
)
text.configure(state="disabled")

root.after(30000, root.destroy)
root.mainloop()
PY
python3 "$editor_app" >"$tmpdir/editor-surface-app.log" 2>&1 &
editor_pid="$!"

chat_app="$tmpdir/chat_surface_app.py"
cat >"$chat_app" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${chat_title}")
root.geometry("1080x760+120+120")
root.configure(bg="#f6f2ea")

header = tk.Frame(root, bg="#f4ede1", height=58)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Proyecto auditoria", fg="#2c2c2c", bg="#f4ede1", font=("DejaVu Sans", 18, "bold")).pack(side="left", padx=18, pady=14)
tk.Label(header, text="Compartir", fg="#2c2c2c", bg="#f4ede1", font=("DejaVu Sans", 13)).pack(side="right", padx=18)

body = tk.Frame(root, bg="#ffffff")
body.pack(fill="both", expand=True)

sidebar = tk.Frame(body, bg="#efe7dc", width=250)
sidebar.pack(side="left", fill="y")
sidebar.pack_propagate(False)
tk.Label(sidebar, text="Nuevo chat", fg="#2c2c2c", bg="#efe7dc", font=("DejaVu Sans", 15, "bold")).pack(anchor="w", padx=16, pady=(18, 8))
for line in ["Biblioteca", "Checklist visual", "Resumen operativo", "Seguimiento OCR"]:
    tk.Label(sidebar, text=line, fg="#3a3a3a", bg="#efe7dc", font=("DejaVu Sans", 13)).pack(anchor="w", padx=20, pady=4)

main = tk.Frame(body, bg="#ffffff")
main.pack(side="left", fill="both", expand=True)
text = tk.Text(main, wrap="word", font=("DejaVu Sans", 14), bg="#ffffff", fg="#222222")
text.pack(fill="both", expand=True, padx=18, pady=18)
text.insert(
    "1.0",
    "Usuario: mirame la pantalla y decime que cambia\\n\\n"
    "Asistente: la lectura visual ya separa OCR, layout y fuentes explicitas.\\n\\n"
    "Usuario: perfecto, prioriza mensajes visibles y el area de input.\\n"
)
text.configure(state="disabled")

footer = tk.Frame(root, bg="#f4ede1", height=72)
footer.pack(fill="x")
footer.pack_propagate(False)
tk.Label(footer, text="Composer Draft", fg="#2c2c2c", bg="#f4ede1", font=("DejaVu Sans", 13, "bold")).pack(side="left", padx=(18, 0), pady=18)
entry = tk.Entry(footer, font=("DejaVu Sans", 14))
entry.insert(0, "Escribi un mensaje")
entry.pack(side="left", fill="x", expand=True, padx=18, pady=18)

root.after(30000, root.destroy)
root.mainloop()
PY
python3 "$chat_app" >"$tmpdir/chat-surface-app.log" 2>&1 &
chat_pid="$!"

terminal_app="$tmpdir/terminal_surface_app.py"
cat >"$terminal_app" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${terminal_title}")
root.geometry("1080x760+160+160")
root.configure(bg="#111111")

header = tk.Frame(root, bg="#202020", height=44)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="lucy@host: ~/golem", fg="#f0f0f0", bg="#202020", font=("DejaVu Sans", 13, "bold")).pack(side="left", padx=16, pady=10)
tk.Label(header, text="Terminal", fg="#c8c8c8", bg="#202020", font=("DejaVu Sans", 12)).pack(side="right", padx=16)

body = tk.Frame(root, bg="#111111")
body.pack(fill="both", expand=True)
text = tk.Text(body, wrap="none", font=("DejaVu Sans Mono", 15), bg="#111111", fg="#d7ffd7", insertbackground="#d7ffd7")
text.pack(fill="both", expand=True, padx=16, pady=16)
text.insert(
    "1.0",
    "lucy@host:~/golem/tests$ pytest -q\\n"
    "visible output block from previous command\\n"
    "lucy@host:~/golem$ rg surface_classification_heuristics scripts\\n"
    "error: smoke terminal classification example\\n"
    "Traceback sample line\\n"
    "exit code 1\\n"
    "lucy@host:~/golem$\\n"
)
text.configure(state="disabled")

root.after(30000, root.destroy)
root.mainloop()
PY
python3 "$terminal_app" >"$tmpdir/terminal-surface-app.log" 2>&1 &
terminal_pid="$!"

browser_app="$tmpdir/browser_surface_app.py"
cat >"$browser_app" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${browser_title}")
root.geometry("1080x760+200+200")
root.configure(bg="#f6f8fb")

header = tk.Frame(root, bg="#1f3b5b", height=58)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Dashboard Overview", fg="#ffffff", bg="#1f3b5b", font=("DejaVu Sans", 18, "bold")).pack(side="left", padx=18, pady=14)
tk.Label(header, text="Settings", fg="#d9e5f2", bg="#1f3b5b", font=("DejaVu Sans", 13)).pack(side="right", padx=18)

body = tk.Frame(root, bg="#f6f8fb")
body.pack(fill="both", expand=True)

sidebar = tk.Frame(body, bg="#dde7f2", width=250)
sidebar.pack(side="left", fill="y")
sidebar.pack_propagate(False)
for line in ["Home", "Sources", "Docs", "Configuration"]:
    tk.Label(sidebar, text=line, fg="#203040", bg="#dde7f2", font=("DejaVu Sans", 14)).pack(anchor="w", padx=18, pady=8)

main = tk.Frame(body, bg="#ffffff")
main.pack(side="left", fill="both", expand=True, padx=18, pady=18)
tk.Label(main, text="Primary Content", fg="#203040", bg="#ffffff", font=("DejaVu Sans", 20, "bold")).pack(anchor="w", padx=18, pady=(18, 10))
text = tk.Text(main, wrap="word", font=("DejaVu Sans", 14), bg="#ffffff", fg="#222222")
text.pack(fill="both", expand=True, padx=18, pady=(0, 18))
text.insert(
    "1.0",
    "Primary content summary for the browser surface.\\n"
    "Open report to continue.\\n"
    "View logs is secondary.\\n"
    "Sources stay visible in the sidebar.\\n"
    "Configuration text remains explicit.\\n"
)
text.configure(state="disabled")

footer = tk.Frame(root, bg="#edf2f7", height=70)
footer.pack(fill="x")
footer.pack_propagate(False)
tk.Label(footer, text="Open Report", fg="#203040", bg="#edf2f7", font=("DejaVu Sans", 15, "bold")).pack(side="left", padx=20, pady=18)
tk.Label(footer, text="View Logs", fg="#203040", bg="#edf2f7", font=("DejaVu Sans", 15)).pack(side="left", padx=18)

root.after(30000, root.destroy)
root.mainloop()
PY
python3 "$browser_app" >"$tmpdir/browser-surface-app.log" 2>&1 &
browser_pid="$!"

editor_wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$editor_title" --timeout 10 --json
)"
chat_wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$chat_title" --timeout 10 --json
)"
terminal_wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$terminal_title" --timeout 10 --json
)"
browser_wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$browser_title" --timeout 10 --json
)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" ./scripts/golem_host_act.sh focus --title "$editor_title" --json >/dev/null
wait_for_active_title "$editor_title"
editor_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh window --title "$editor_title" --json
)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" ./scripts/golem_host_act.sh focus --title "$chat_title" --json >/dev/null
wait_for_active_title "$chat_title"
chat_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh window --title "$chat_title" --json
)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" ./scripts/golem_host_act.sh focus --title "$terminal_title" --json >/dev/null
wait_for_active_title "$terminal_title"
terminal_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh active-window --json
)"

GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" ./scripts/golem_host_act.sh focus --title "$browser_title" --json >/dev/null
wait_for_active_title "$browser_title"
browser_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh window --title "$browser_title" --json
)"

python3 - "$editor_json" "$chat_json" "$terminal_json" "$browser_json" "$editor_wait_json" "$chat_wait_json" "$terminal_wait_json" "$browser_wait_json" "$editor_title" "$chat_title" "$terminal_title" "$browser_title" <<'PY'
import json
import pathlib
import sys

editor_payload = json.loads(sys.argv[1])
chat_payload = json.loads(sys.argv[2])
terminal_payload = json.loads(sys.argv[3])
browser_payload = json.loads(sys.argv[4])
editor_wait = json.loads(sys.argv[5])
chat_wait = json.loads(sys.argv[6])
terminal_wait = json.loads(sys.argv[7])
browser_wait = json.loads(sys.argv[8])
editor_title = sys.argv[9]
chat_title = sys.argv[10]
terminal_title = sys.argv[11]
browser_title = sys.argv[12]


def assert_payload(payload, expected_category, allowed_kinds, required_fields, required_fine_fields, required_contextual_fields):
    description = payload["description"]
    classification = description["surface_classification"]
    useful_lines = description["useful_lines"]
    useful_regions = description["useful_regions"]
    structured_fields = description["structured_fields"]
    fine_fields = structured_fields["fine_fields"]
    contextual_refinements = structured_fields["contextual_refinements"]

    assert classification["category"] == expected_category, classification
    assert classification["confidence"] in {"strong", "reasonable"}, classification
    assert useful_lines, useful_lines
    assert useful_regions, useful_regions
    assert "surface_classification_heuristics" in payload["sources_used"], payload["sources_used"]
    assert "structured_fields_heuristics" in payload["sources_used"], payload["sources_used"]
    assert "contextual_refinement_heuristics" in payload["sources_used"], payload["sources_used"]
    assert "surface_profile" in payload["artifacts"], payload["artifacts"]
    assert "structured_fields" in payload["artifacts"], payload["artifacts"]
    surface_profile_path = pathlib.Path(payload["artifacts"]["surface_profile"])
    structured_fields_path = pathlib.Path(payload["artifacts"]["structured_fields"])
    assert surface_profile_path.exists(), surface_profile_path
    assert structured_fields_path.exists(), structured_fields_path
    surface_profile = json.loads(surface_profile_path.read_text(encoding="utf-8"))
    stored_structured_fields = json.loads(structured_fields_path.read_text(encoding="utf-8"))
    assert surface_profile["surface_classification"]["category"] == expected_category, surface_profile
    assert structured_fields["category"] == expected_category, structured_fields
    assert stored_structured_fields["category"] == expected_category, stored_structured_fields
    assert structured_fields["attempted_fine_fields"], structured_fields
    assert stored_structured_fields["attempted_fine_fields"], stored_structured_fields
    assert structured_fields["attempted_contextual_refinements"], structured_fields
    assert stored_structured_fields["attempted_contextual_refinements"], stored_structured_fields
    kinds = {item["priority_kind"] for item in useful_lines}
    assert kinds & set(allowed_kinds), kinds
    assert "surface classification heuristics read the visible target as" in description["summary"].lower(), description["summary"]
    assert "surface_classification_heuristics" in description["source_breakdown"], description["source_breakdown"]
    assert "structured_fields_heuristics" in description["source_breakdown"], description["source_breakdown"]
    assert "contextual_refinement_heuristics" in description["source_breakdown"], description["source_breakdown"]
    for field_name in required_fields:
        entries = structured_fields["fields"].get(field_name) or []
        assert entries, (field_name, structured_fields)
        for entry in entries[:2]:
            assert entry["value"], entry
            assert entry["confidence"] in {"high", "medium", "low"}, entry
            assert entry["source_refs"], entry
    for field_name in required_fine_fields:
        entries = fine_fields.get(field_name) or []
        stored_entries = stored_structured_fields["fine_fields"].get(field_name) or []
        assert entries, (field_name, fine_fields)
        assert stored_entries, (field_name, stored_structured_fields["fine_fields"])
        for entry in entries[:2]:
            assert entry["value"], entry
            assert entry["confidence"] in {"high", "medium", "low"}, entry
            assert entry["source_refs"], entry
    for field_name in required_contextual_fields:
        entries = contextual_refinements.get(field_name) or []
        stored_entries = stored_structured_fields["contextual_refinements"].get(field_name) or []
        assert entries, (field_name, contextual_refinements)
        assert stored_entries, (field_name, stored_structured_fields["contextual_refinements"])
        for entry in entries[:2]:
            assert entry["value"], entry
            assert entry["confidence"] in {"high", "medium", "low"}, entry
            assert entry["source_refs"], entry
            assert entry["priority"] in {"primary", "secondary"}, entry
            assert entry["activity_state"] in {"active", "visible", "current", "recent", "historical"}, entry
    return classification, useful_lines, kinds, structured_fields, fine_fields, contextual_refinements


editor_classification, editor_lines, editor_kinds, editor_structured, editor_fine, editor_context = assert_payload(
    editor_payload,
    "editor",
    {"error-line", "file-reference", "code-line", "explorer-item", "workspace-header"},
    {"workspace_or_project", "file_or_tab_candidates", "active_editor_text_snippets"},
    {"active_file_candidate", "visible_tab_candidates", "workspace_or_project_candidate", "explorer_context_candidates"},
    {"active_tab_candidate", "visible_tab_candidates", "primary_error_candidate", "active_file_candidate", "sidebar_context_candidates"},
)
chat_classification, chat_lines, chat_kinds, chat_structured, chat_fine, chat_context = assert_payload(
    chat_payload,
    "chat",
    {"visible-message", "composer", "conversation-sidebar"},
    {"conversation_title_candidates", "visible_message_snippets", "sidebar_chat_candidates"},
    {"conversation_title_candidate", "visible_message_snippets", "input_box_candidate", "sidebar_conversation_candidates"},
    {"active_conversation_candidate", "sidebar_conversation_candidates", "input_box_candidate", "visible_message_snippets", "composer_text_candidate"},
)
terminal_classification, terminal_lines, terminal_kinds, terminal_structured, terminal_fine, terminal_context = assert_payload(
    terminal_payload,
    "terminal",
    {"command-or-prompt", "error-output", "visible-output"},
    {"prompt_candidates", "command_candidates", "error_output_candidates"},
    {"active_prompt_candidate", "recent_command_candidate", "primary_error_output_candidate", "recent_output_block_snippets"},
    {"active_prompt_candidate", "historical_prompt_candidates", "recent_command_candidate", "primary_error_output_candidate", "recent_output_block_snippets"},
)
browser_classification, browser_lines, browser_kinds, browser_structured, browser_fine, browser_context = assert_payload(
    browser_payload,
    "browser-web-app",
    {"page-header", "navigation", "page-content", "cta-or-control"},
    {"page_title_candidates", "header_text", "primary_content_snippets", "cta_or_action_text_candidates"},
    {"primary_header_candidate", "sidebar_navigation_candidates", "primary_cta_candidate", "main_content_snippets", "page_title_candidate"},
    {"primary_header_candidate", "primary_cta_candidate", "secondary_action_candidates", "sidebar_navigation_candidates", "main_content_snippets"},
)

assert editor_context["active_tab_candidate"][0]["value"] != editor_context["visible_tab_candidates"][0]["value"], editor_context
assert "error:" in editor_context["primary_error_candidate"][0]["value"].lower(), editor_context
assert editor_context["primary_error_candidate"][0]["priority"] == "primary", editor_context
assert chat_context["active_conversation_candidate"][0]["value"] != chat_context["sidebar_conversation_candidates"][0]["value"], chat_context
assert "mensaje" in json.dumps(chat_context["input_box_candidate"], ensure_ascii=False).lower() or "composer" in json.dumps(chat_context["composer_text_candidate"], ensure_ascii=False).lower(), chat_context
assert terminal_context["active_prompt_candidate"][0]["value"] != terminal_context["historical_prompt_candidates"][0]["value"], terminal_context
assert "rg surface_classification_heuristics scripts" in json.dumps(terminal_context["recent_command_candidate"], ensure_ascii=False), terminal_context
assert any(token in terminal_context["primary_error_output_candidate"][0]["value"].lower() for token in ["error:", "traceback"]), terminal_context
assert "Open Report" in json.dumps(browser_context["primary_cta_candidate"], ensure_ascii=False), browser_context
assert "View Logs" in json.dumps(browser_context["secondary_action_candidates"], ensure_ascii=False), browser_context
assert "Home" in json.dumps(browser_context["sidebar_navigation_candidates"], ensure_ascii=False) or "Sources" in json.dumps(browser_context["sidebar_navigation_candidates"], ensure_ascii=False), browser_context
assert "Primary content" in json.dumps(browser_context["main_content_snippets"], ensure_ascii=False) or "browser surface" in json.dumps(browser_context["main_content_snippets"], ensure_ascii=False), browser_context

assert editor_title in editor_payload["description"]["target_window"]["title"], editor_payload["description"]["target_window"]
assert chat_title in chat_payload["description"]["target_window"]["title"], chat_payload["description"]["target_window"]
assert terminal_title in terminal_payload["description"]["target_window"]["title"], terminal_payload["description"]["target_window"]
assert browser_title in browser_payload["description"]["target_window"]["title"], browser_payload["description"]["target_window"]
assert editor_wait["window"]["title"] == editor_title, editor_wait
assert chat_wait["window"]["title"] == chat_title, chat_wait
assert terminal_wait["window"]["title"] == terminal_title, terminal_wait
assert browser_wait["window"]["title"] == browser_title, browser_wait

print("SMOKE_HOST_DESCRIBE_SURFACE_PROFILES_OK")
print("HOST_DESCRIBE_EDITOR_MODE synthetic")
print("HOST_DESCRIBE_CHAT_MODE synthetic")
print(f"HOST_DESCRIBE_EDITOR_SURFACE {editor_classification['category']}:{editor_classification['confidence']}:{sorted(editor_kinds)}")
print(f"HOST_DESCRIBE_CHAT_SURFACE {chat_classification['category']}:{chat_classification['confidence']}:{sorted(chat_kinds)}")
print(f"HOST_DESCRIBE_TERMINAL_SURFACE {terminal_classification['category']}:{terminal_classification['confidence']}:{sorted(terminal_kinds)}")
print(f"HOST_DESCRIBE_BROWSER_SURFACE {browser_classification['category']}:{browser_classification['confidence']}:{sorted(browser_kinds)}")
print(f"HOST_DESCRIBE_EDITOR_RUN_DIR {editor_payload['run_dir']}")
print(f"HOST_DESCRIBE_CHAT_RUN_DIR {chat_payload['run_dir']}")
print(f"HOST_DESCRIBE_TERMINAL_RUN_DIR {terminal_payload['run_dir']}")
print(f"HOST_DESCRIBE_BROWSER_RUN_DIR {browser_payload['run_dir']}")
print(f"HOST_DESCRIBE_EDITOR_LINE {editor_lines[0]['text']}")
print(f"HOST_DESCRIBE_CHAT_LINE {chat_lines[0]['text']}")
print(f"HOST_DESCRIBE_TERMINAL_LINE {terminal_lines[0]['text']}")
print(f"HOST_DESCRIBE_BROWSER_LINE {browser_lines[0]['text']}")
print(f"HOST_DESCRIBE_EDITOR_FIELDS {editor_structured['non_empty_fields']}")
print(f"HOST_DESCRIBE_CHAT_FIELDS {chat_structured['non_empty_fields']}")
print(f"HOST_DESCRIBE_TERMINAL_FIELDS {terminal_structured['non_empty_fields']}")
print(f"HOST_DESCRIBE_BROWSER_FIELDS {browser_structured['non_empty_fields']}")
print(f"HOST_DESCRIBE_EDITOR_FINE_FIELDS {editor_structured['non_empty_fine_fields']}")
print(f"HOST_DESCRIBE_CHAT_FINE_FIELDS {chat_structured['non_empty_fine_fields']}")
print(f"HOST_DESCRIBE_TERMINAL_FINE_FIELDS {terminal_structured['non_empty_fine_fields']}")
print(f"HOST_DESCRIBE_BROWSER_FINE_FIELDS {browser_structured['non_empty_fine_fields']}")
print(f"HOST_DESCRIBE_EDITOR_CONTEXTUAL {editor_structured['non_empty_contextual_refinements']}")
print(f"HOST_DESCRIBE_CHAT_CONTEXTUAL {chat_structured['non_empty_contextual_refinements']}")
print(f"HOST_DESCRIBE_TERMINAL_CONTEXTUAL {terminal_structured['non_empty_contextual_refinements']}")
print(f"HOST_DESCRIBE_BROWSER_CONTEXTUAL {browser_structured['non_empty_contextual_refinements']}")
PY
