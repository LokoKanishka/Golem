#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/golem_host_capability_common.sh
source "${SCRIPT_DIR}/golem_host_capability_common.sh"

SCREENSHOT_HELPER="${GOLEM_SCREENSHOT_HELPER:-$HOME/.codex/skills/screenshot/scripts/take_screenshot.py}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_perceive.sh
  ./scripts/golem_host_perceive.sh snapshot [--json]
  ./scripts/golem_host_perceive.sh path
  ./scripts/golem_host_perceive.sh json

Env overrides:
  GOLEM_HOST_CAPABILITIES_ROOT
  GOLEM_SCREENSHOT_HELPER
EOF
}

snapshot() {
  local run_dir desktop_png active_png windows_txt active_props_txt summary_path manifest_path
  local active_window_id active_window_title session_type display_name

  golem_host_capabilities_require_tools python3 wmctrl xdotool
  [ -f "$SCREENSHOT_HELPER" ] || {
    printf 'ERROR: screenshot helper not found: %s\n' "$SCREENSHOT_HELPER" >&2
    exit 1
  }

  run_dir="$(golem_host_capabilities_create_dir perceive)"
  desktop_png="${run_dir}/desktop-root.png"
  active_png="${run_dir}/active-window.png"
  windows_txt="${run_dir}/windows.txt"
  active_props_txt="${run_dir}/active-window-properties.txt"
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"

  active_window_id="$(xdotool getactivewindow 2>/dev/null)"
  active_window_title="$(xdotool getwindowname "$active_window_id" 2>/dev/null || true)"
  session_type="${XDG_SESSION_TYPE:-unknown}"
  display_name="${DISPLAY:-unset}"

  python3 "$SCREENSHOT_HELPER" --path "$desktop_png" >/dev/null 2>&1
  python3 "$SCREENSHOT_HELPER" --path "$active_png" --active-window >/dev/null 2>&1
  wmctrl -lp >"$windows_txt"
  xprop -id "$active_window_id" WM_CLASS _NET_WM_PID WM_NAME >"$active_props_txt" 2>&1 || true

  python3 - "$run_dir" "$windows_txt" "$desktop_png" "$active_png" "$active_window_id" "$active_window_title" "$display_name" "$session_type" "$summary_path" "$manifest_path" <<'PY'
import json
import os
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
windows_txt = pathlib.Path(sys.argv[2])
desktop_png = pathlib.Path(sys.argv[3])
active_png = pathlib.Path(sys.argv[4])
active_window_id = sys.argv[5]
active_window_title = sys.argv[6]
display_name = sys.argv[7]
session_type = sys.argv[8]
summary_path = pathlib.Path(sys.argv[9])
manifest_path = pathlib.Path(sys.argv[10])

windows = []
for raw_line in windows_txt.read_text(encoding="utf-8").splitlines():
    line = raw_line.rstrip()
    if not line:
      continue
    parts = line.split(None, 4)
    if len(parts) < 5:
      continue
    window_id, desktop, pid, host, title = parts
    windows.append(
        {
            "window_id": window_id,
            "desktop": desktop,
            "pid": pid,
            "host": host,
            "title": title,
        }
    )

top_titles = [item["title"] for item in windows if item["title"] and item["title"] != "Desktop Icons 1"][:5]

summary_lines = [
    "GOLEM HOST PERCEPTION",
    "",
    f"run_dir: {run_dir}",
    f"display: {display_name}",
    f"session_type: {session_type}",
    f"desktop_screenshot: {desktop_png}",
    f"active_window_screenshot: {active_png}",
    f"active_window_id: {active_window_id or '(none)'}",
    f"active_window_title: {active_window_title or '(none)'}",
    f"windows_total: {len(windows)}",
    "visible_context:",
]
summary_lines.extend(f"- {title}" for title in top_titles)
if not top_titles:
    summary_lines.append("- (no titled windows found)")

summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

manifest = {
    "kind": "golem_host_perceive",
    "run_dir": str(run_dir),
    "display": display_name,
    "session_type": session_type,
    "artifacts": {
        "summary": str(summary_path),
        "desktop_screenshot": str(desktop_png),
        "active_window_screenshot": str(active_png),
        "windows": str(windows_txt),
        "active_window_properties": str(run_dir / "active-window-properties.txt"),
    },
    "active_window": {
        "window_id": active_window_id,
        "title": active_window_title,
    },
    "windows_total": len(windows),
    "visible_context": top_titles,
    "windows": windows,
    "file_sizes": {
        "desktop_screenshot": desktop_png.stat().st_size if desktop_png.exists() else 0,
        "active_window_screenshot": active_png.stat().st_size if active_png.exists() else 0,
    },
}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

  golem_host_capabilities_emit "text" "$summary_path" "$manifest_path" "GOLEM HOST PERCEPTION"
}

latest() {
  local run_dir="$1"
  local summary_path manifest_path
  run_dir="$(golem_host_capabilities_latest_dir perceive)"
  [ -n "$run_dir" ] || {
    printf 'FAIL: no host perception runs found under %s\n' "$GOLEM_HOST_CAPABILITIES_ROOT" >&2
    exit 1
  }
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"
  golem_host_capabilities_emit "$1" "$summary_path" "$manifest_path" "GOLEM HOST PERCEPTION"
}

main() {
  local mode="${1:-snapshot}"
  local format="text"

  case "$mode" in
    snapshot)
      shift || true
      if [ "${1:-}" = "--json" ]; then
        format="json"
      elif [ "$#" -gt 0 ]; then
        usage >&2
        exit 2
      fi
      if [ "$format" = "json" ]; then
        snapshot >/dev/null
        latest json
      else
        snapshot
      fi
      ;;
    path)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest path
      ;;
    json)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest json
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
