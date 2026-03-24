#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
editor_title="Visual Studio Code - Golem Editor Surface Smoke $$ [synthetic]"
chat_title="ChatGPT - Golem Chat Surface Smoke $$ [synthetic]"
terminal_title="Golem Terminal Surface Smoke $$ [synthetic]"
editor_pid=""
chat_pid=""
terminal_pid=""

wait_for_active_title() {
  local expected="$1"
  local active_title=""
  for _ in $(seq 1 50); do
    active_title="$(xdotool getactivewindow getwindowname 2>/dev/null || true)"
    if [[ "$active_title" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done
  printf 'FAIL: active window did not settle on expected title: %s (last=%s)\n' "$expected" "$active_title" >&2
  return 1
}

cleanup() {
  for pid in "$editor_pid" "$chat_pid" "$terminal_pid"; do
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
    "error: score_line_for_category mismatch\\n"
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
tk.Label(header, text="Chat Workspace", fg="#2c2c2c", bg="#f4ede1", font=("DejaVu Sans", 18, "bold")).pack(side="left", padx=18, pady=14)
tk.Label(header, text="Compartir", fg="#2c2c2c", bg="#f4ede1", font=("DejaVu Sans", 13)).pack(side="right", padx=18)

body = tk.Frame(root, bg="#ffffff")
body.pack(fill="both", expand=True)

sidebar = tk.Frame(body, bg="#efe7dc", width=250)
sidebar.pack(side="left", fill="y")
sidebar.pack_propagate(False)
tk.Label(sidebar, text="Nuevo chat", fg="#2c2c2c", bg="#efe7dc", font=("DejaVu Sans", 15, "bold")).pack(anchor="w", padx=16, pady=(18, 8))
for line in ["Biblioteca", "Proyecto auditoria", "Checklist visual", "Resumen operativo"]:
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
    "lucy@host:~/golem$ python3 scripts/golem_host_describe.sh\\n"
    "lucy@host:~/golem$ rg surface_classification_heuristics scripts\\n"
    "error: smoke terminal classification example\\n"
    "Traceback sample line\\n"
    "exit code 1\\n"
    "visible output block stays on screen\\n"
)
text.configure(state="disabled")

root.after(30000, root.destroy)
root.mainloop()
PY
python3 "$terminal_app" >"$tmpdir/terminal-surface-app.log" 2>&1 &
terminal_pid="$!"

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

python3 - "$editor_json" "$chat_json" "$terminal_json" "$editor_wait_json" "$chat_wait_json" "$terminal_wait_json" "$editor_title" "$chat_title" "$terminal_title" <<'PY'
import json
import pathlib
import sys

editor_payload = json.loads(sys.argv[1])
chat_payload = json.loads(sys.argv[2])
terminal_payload = json.loads(sys.argv[3])
editor_wait = json.loads(sys.argv[4])
chat_wait = json.loads(sys.argv[5])
terminal_wait = json.loads(sys.argv[6])
editor_title = sys.argv[7]
chat_title = sys.argv[8]
terminal_title = sys.argv[9]


def assert_payload(payload, expected_category, allowed_kinds):
    description = payload["description"]
    classification = description["surface_classification"]
    useful_lines = description["useful_lines"]
    useful_regions = description["useful_regions"]

    assert classification["category"] == expected_category, classification
    assert classification["confidence"] in {"strong", "reasonable"}, classification
    assert useful_lines, useful_lines
    assert useful_regions, useful_regions
    assert "surface_classification_heuristics" in payload["sources_used"], payload["sources_used"]
    assert "surface_profile" in payload["artifacts"], payload["artifacts"]
    surface_profile_path = pathlib.Path(payload["artifacts"]["surface_profile"])
    assert surface_profile_path.exists(), surface_profile_path
    surface_profile = json.loads(surface_profile_path.read_text(encoding="utf-8"))
    assert surface_profile["surface_classification"]["category"] == expected_category, surface_profile
    kinds = {item["priority_kind"] for item in useful_lines}
    assert kinds & set(allowed_kinds), kinds
    assert "surface classification heuristics read the visible target as" in description["summary"].lower(), description["summary"]
    assert "surface_classification_heuristics" in description["source_breakdown"], description["source_breakdown"]
    return classification, useful_lines, kinds


editor_classification, editor_lines, editor_kinds = assert_payload(
    editor_payload,
    "editor",
    {"error-line", "file-reference", "code-line", "explorer-item", "workspace-header"},
)
chat_classification, chat_lines, chat_kinds = assert_payload(
    chat_payload,
    "chat",
    {"visible-message", "composer", "conversation-sidebar"},
)
terminal_classification, terminal_lines, terminal_kinds = assert_payload(
    terminal_payload,
    "terminal",
    {"command-or-prompt", "error-output", "visible-output"},
)

assert editor_title in editor_payload["description"]["target_window"]["title"], editor_payload["description"]["target_window"]
assert chat_title in chat_payload["description"]["target_window"]["title"], chat_payload["description"]["target_window"]
assert terminal_title in terminal_payload["description"]["target_window"]["title"], terminal_payload["description"]["target_window"]
assert editor_wait["window"]["title"] == editor_title, editor_wait
assert chat_wait["window"]["title"] == chat_title, chat_wait
assert terminal_wait["window"]["title"] == terminal_title, terminal_wait

print("SMOKE_HOST_DESCRIBE_SURFACE_PROFILES_OK")
print("HOST_DESCRIBE_EDITOR_MODE synthetic")
print("HOST_DESCRIBE_CHAT_MODE synthetic")
print(f"HOST_DESCRIBE_EDITOR_SURFACE {editor_classification['category']}:{editor_classification['confidence']}:{sorted(editor_kinds)}")
print(f"HOST_DESCRIBE_CHAT_SURFACE {chat_classification['category']}:{chat_classification['confidence']}:{sorted(chat_kinds)}")
print(f"HOST_DESCRIBE_TERMINAL_SURFACE {terminal_classification['category']}:{terminal_classification['confidence']}:{sorted(terminal_kinds)}")
print(f"HOST_DESCRIBE_EDITOR_RUN_DIR {editor_payload['run_dir']}")
print(f"HOST_DESCRIBE_CHAT_RUN_DIR {chat_payload['run_dir']}")
print(f"HOST_DESCRIBE_TERMINAL_RUN_DIR {terminal_payload['run_dir']}")
print(f"HOST_DESCRIBE_EDITOR_LINE {editor_lines[0]['text']}")
print(f"HOST_DESCRIBE_CHAT_LINE {chat_lines[0]['text']}")
print(f"HOST_DESCRIBE_TERMINAL_LINE {terminal_lines[0]['text']}")
PY
