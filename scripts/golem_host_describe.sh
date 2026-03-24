#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/golem_host_capability_common.sh
source "${SCRIPT_DIR}/golem_host_capability_common.sh"

SCREENSHOT_HELPER="${GOLEM_SCREENSHOT_HELPER:-$HOME/.codex/skills/screenshot/scripts/take_screenshot.py}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_describe.sh
  ./scripts/golem_host_describe.sh desktop [--json]
  ./scripts/golem_host_describe.sh snapshot [--json]
  ./scripts/golem_host_describe.sh active-window [--json]
  ./scripts/golem_host_describe.sh window (--window-id <id> | --title <substring>) [--json]
  ./scripts/golem_host_describe.sh path
  ./scripts/golem_host_describe.sh json

Env overrides:
  GOLEM_HOST_CAPABILITIES_ROOT
  GOLEM_SCREENSHOT_HELPER
EOF
}

emit_run() {
  local format="$1"
  local run_dir="$2"
  golem_host_capabilities_emit "$format" "${run_dir}/summary.txt" "${run_dir}/manifest.json" "GOLEM HOST SEMANTIC DESCRIPTION"
}

latest() {
  local run_dir
  run_dir="$(golem_host_capabilities_latest_dir describe)"
  [ -n "$run_dir" ] || {
    printf 'FAIL: no host semantic description runs found under %s\n' "$GOLEM_HOST_CAPABILITIES_ROOT" >&2
    exit 1
  }
  emit_run "$1" "$run_dir"
}

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dest"
  fi
}

window_id_to_decimal() {
  python3 - "$1" <<'PY'
import sys

raw = sys.argv[1].strip()
if not raw:
    raise SystemExit("missing window id")
value = int(raw, 16) if raw.lower().startswith("0x") else int(raw)
print(value)
PY
}

main() {
  local mode="${1:-desktop}"
  local format="text"
  local requested_title=""
  local requested_window_id=""

  case "$mode" in
    path)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest path
      return 0
      ;;
    json)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest json
      return 0
      ;;
  esac

  shift || true
  if [ "$#" -gt 0 ] && [ "${!#}" = "--json" ]; then
    format="json"
    set -- "${@:1:$(($#-1))}"
  fi

  case "$mode" in
    desktop|snapshot)
      mode="desktop"
      [ "$#" -eq 0 ] || { usage >&2; exit 2; }
      ;;
    active-window)
      [ "$#" -eq 0 ] || { usage >&2; exit 2; }
      ;;
    window)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --window-id)
            requested_window_id="${2:-}"
            shift 2
            ;;
          --title)
            requested_title="${2:-}"
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done
      if [ -n "$requested_window_id" ] && [ -n "$requested_title" ]; then
        printf 'FAIL: choose either --window-id or --title, not both\n' >&2
        exit 2
      fi
      if [ -z "$requested_window_id" ] && [ -z "$requested_title" ]; then
        usage >&2
        exit 2
      fi
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  golem_host_capabilities_require_tools python3 wmctrl xdotool xprop identify tesseract ps
  [ -f "$SCREENSHOT_HELPER" ] || {
    printf 'ERROR: screenshot helper not found: %s\n' "$SCREENSHOT_HELPER" >&2
    exit 1
  }

  local perceive_json run_dir summary_path manifest_path description_path sources_path
  local selection_path windows_json_path desktops_txt root_props_txt target_props_txt target_process_txt
  local source_manifest_copy source_windows_txt source_active_props_txt target_screenshot size_txt
  local ocr_txt ocr_tsv supporting_active_png
  local perceive_run_dir perceive_manifest_path perceive_windows_txt perceive_active_props perceive_desktop_png perceive_active_png
  local resolved_window_id resolved_window_pid resolved_window_title matched_window_count selection_reason

  perceive_json="$("${SCRIPT_DIR}/golem_host_perceive.sh" snapshot --json)"
  run_dir="$(golem_host_capabilities_create_dir describe)"
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"
  description_path="${run_dir}/description.json"
  sources_path="${run_dir}/sources.json"
  selection_path="${run_dir}/selection.json"
  windows_json_path="${run_dir}/windows.json"
  desktops_txt="${run_dir}/desktops.txt"
  root_props_txt="${run_dir}/root-properties.txt"
  target_props_txt="${run_dir}/target-window-properties.txt"
  target_process_txt="${run_dir}/target-process.txt"
  source_manifest_copy="${run_dir}/source-perceive-manifest.json"
  source_windows_txt="${run_dir}/windows.txt"
  source_active_props_txt="${run_dir}/active-window-properties.txt"
  supporting_active_png="${run_dir}/supporting-active-window.png"
  size_txt="${run_dir}/target-screenshot-size.txt"
  ocr_txt="${run_dir}/ocr.txt"
  ocr_tsv="${run_dir}/ocr.tsv"

  readarray -t perceive_meta < <(python3 - "$perceive_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload["run_dir"])
print(payload["artifacts"]["windows"])
print(payload["artifacts"]["active_window_properties"])
print(payload["artifacts"]["desktop_screenshot"])
print(payload["artifacts"]["active_window_screenshot"])
PY
)

  perceive_run_dir="${perceive_meta[0]}"
  perceive_manifest_path="${perceive_run_dir}/manifest.json"
  perceive_windows_txt="${perceive_meta[1]}"
  perceive_active_props="${perceive_meta[2]}"
  perceive_desktop_png="${perceive_meta[3]}"
  perceive_active_png="${perceive_meta[4]}"

  cp "$perceive_manifest_path" "$source_manifest_copy"
  cp "$perceive_windows_txt" "$source_windows_txt"
  copy_if_exists "$perceive_active_props" "$source_active_props_txt"
  if [ "$mode" = "desktop" ]; then
    copy_if_exists "$perceive_active_png" "$supporting_active_png"
  fi

  wmctrl -d >"$desktops_txt"
  xprop -root _NET_ACTIVE_WINDOW _NET_CURRENT_DESKTOP >"$root_props_txt" 2>&1 || true

  python3 - "$perceive_json" "$windows_json_path" "$selection_path" "$mode" "$requested_window_id" "$requested_title" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
windows_json_path = sys.argv[2]
selection_path = sys.argv[3]
target_kind = sys.argv[4]
requested_window_id = sys.argv[5].strip()
requested_title = sys.argv[6]


def normalize_window_id(raw):
    if raw is None:
        return None
    value = str(raw).strip()
    if not value:
        return None
    try:
        parsed = int(value, 16) if value.lower().startswith("0x") else int(value)
    except ValueError:
        return None
    return parsed


def enrich_window(item, *, is_active=False):
    enriched = dict(item)
    enriched["window_id_int"] = normalize_window_id(item.get("window_id"))
    enriched["is_active"] = is_active
    return enriched


active_payload = payload.get("active_window") or {}
active_id_int = normalize_window_id(active_payload.get("window_id"))
windows = [enrich_window(item) for item in payload.get("windows", [])]

active_match = None
for item in windows:
    if active_id_int is not None and item.get("window_id_int") == active_id_int:
        item["is_active"] = True
        active_match = item
        break

if active_match is None and active_payload.get("title"):
    for item in windows:
        if item.get("title") == active_payload.get("title"):
            item["is_active"] = True
            active_match = item
            break

if active_match is None:
    active_match = enrich_window(
        {
            "window_id": active_payload.get("window_id") or "",
            "desktop": "",
            "pid": "",
            "host": "",
            "title": active_payload.get("title") or "",
        },
        is_active=True,
    )

selection_reason = ""
matched_candidates = []

if target_kind in {"desktop", "active-window"}:
    resolved = active_match
    selection_reason = "active-window-from-perception"
    matched_candidates = [active_match]
else:
    if requested_window_id:
      requested_id_int = normalize_window_id(requested_window_id)
      matched_candidates = [
          item for item in windows if item.get("window_id_int") == requested_id_int
      ]
      if not matched_candidates:
          raise SystemExit(f'FAIL: no window matched window_id "{requested_window_id}"')
      resolved = matched_candidates[0]
      selection_reason = "requested-window-id"
    else:
      needle = requested_title.lower()
      matched_candidates = [
          item for item in windows if needle in (item.get("title") or "").lower()
      ]
      if not matched_candidates:
          raise SystemExit(f'FAIL: no window title contained "{requested_title}"')
      active_candidates = [item for item in matched_candidates if item.get("is_active")]
      if active_candidates:
          resolved = active_candidates[0]
          selection_reason = "active-title-match"
      else:
          resolved = matched_candidates[0]
          selection_reason = "first-title-match"

json.dump(
    {
        "windows_total": len(windows),
        "windows": windows,
    },
    open(windows_json_path, "w", encoding="utf-8"),
    indent=2,
    ensure_ascii=True,
)
with open(windows_json_path, "a", encoding="utf-8") as fh:
    fh.write("\n")

selection = {
    "target_kind": target_kind,
    "requested": {
        "window_id": requested_window_id or None,
        "title": requested_title or None,
    },
    "selection_reason": selection_reason,
    "matched_window_count": len(matched_candidates),
    "matched_candidates": [
        {
            "window_id": item.get("window_id"),
            "title": item.get("title"),
            "desktop": item.get("desktop"),
            "pid": item.get("pid"),
            "is_active": bool(item.get("is_active")),
        }
        for item in matched_candidates[:10]
    ],
    "resolved_window": {
        "window_id": resolved.get("window_id"),
        "window_id_int": resolved.get("window_id_int"),
        "title": resolved.get("title"),
        "desktop": resolved.get("desktop"),
        "pid": resolved.get("pid"),
        "host": resolved.get("host"),
        "is_active": bool(resolved.get("is_active")),
    },
    "active_window": {
        "window_id": active_match.get("window_id"),
        "window_id_int": active_match.get("window_id_int"),
        "title": active_match.get("title"),
        "desktop": active_match.get("desktop"),
        "pid": active_match.get("pid"),
        "host": active_match.get("host"),
    },
}
with open(selection_path, "w", encoding="utf-8") as fh:
    json.dump(selection, fh, indent=2, ensure_ascii=True)
    fh.write("\n")
PY

  readarray -t selection_meta < <(python3 - "$selection_path" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())
resolved = payload["resolved_window"]
print(resolved.get("window_id") or "")
print(resolved.get("pid") or "")
print(resolved.get("title") or "")
print(payload.get("matched_window_count") or 0)
print(payload.get("selection_reason") or "")
PY
)

  resolved_window_id="${selection_meta[0]}"
  resolved_window_pid="${selection_meta[1]}"
  resolved_window_title="${selection_meta[2]}"
  matched_window_count="${selection_meta[3]}"
  selection_reason="${selection_meta[4]}"

  case "$mode" in
    desktop)
      target_screenshot="${run_dir}/target-desktop.png"
      cp "$perceive_desktop_png" "$target_screenshot"
      ;;
    active-window)
      target_screenshot="${run_dir}/target-active-window.png"
      cp "$perceive_active_png" "$target_screenshot"
      ;;
    window)
      local decimal_window_id
      decimal_window_id="$(window_id_to_decimal "$resolved_window_id")"
      target_screenshot="${run_dir}/target-window.png"
      python3 "$SCREENSHOT_HELPER" --path "$target_screenshot" --window-id "$decimal_window_id" >/dev/null 2>&1
      ;;
  esac

  if [ -n "$resolved_window_id" ]; then
    xprop -id "$resolved_window_id" WM_CLASS _NET_WM_PID WM_NAME >"$target_props_txt" 2>&1 || true
  else
    printf 'window metadata unavailable\n' >"$target_props_txt"
  fi

  if [ -n "$resolved_window_pid" ] && [ "$resolved_window_pid" != "0" ]; then
    ps -p "$resolved_window_pid" -o pid=,comm=,args= >"$target_process_txt" 2>&1 || true
  else
    printf 'pid unavailable\n' >"$target_process_txt"
  fi

  identify -format '%wx%h' "$target_screenshot" >"$size_txt"
  tesseract "$target_screenshot" "${run_dir}/ocr" --psm 6 >/dev/null 2>&1 || true
  [ -f "$ocr_txt" ] || : >"$ocr_txt"
  tesseract "$target_screenshot" "${run_dir}/ocr" --psm 6 tsv >/dev/null 2>&1 || true
  if [ -f "${run_dir}/ocr.tsv" ] && [ "${run_dir}/ocr.tsv" != "$ocr_tsv" ]; then
    mv "${run_dir}/ocr.tsv" "$ocr_tsv"
  elif [ -f "${run_dir}/ocr.txt.tsv" ]; then
    mv "${run_dir}/ocr.txt.tsv" "$ocr_tsv"
  elif [ -f "${run_dir}/ocr.tsv.txt" ]; then
    mv "${run_dir}/ocr.tsv.txt" "$ocr_tsv"
  else
    printf 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n' >"$ocr_tsv"
  fi

  python3 - "$run_dir" "$summary_path" "$manifest_path" "$description_path" "$sources_path" "$selection_path" "$windows_json_path" "$desktops_txt" "$root_props_txt" "$target_props_txt" "$target_process_txt" "$target_screenshot" "$size_txt" "$ocr_txt" "$ocr_tsv" "$source_manifest_copy" "$source_windows_txt" "$source_active_props_txt" "$supporting_active_png" <<'PY'
import csv
import json
import pathlib
import re
import statistics
import sys

run_dir = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
description_path = pathlib.Path(sys.argv[4])
sources_path = pathlib.Path(sys.argv[5])
selection_path = pathlib.Path(sys.argv[6])
windows_json_path = pathlib.Path(sys.argv[7])
desktops_txt = pathlib.Path(sys.argv[8])
root_props_txt = pathlib.Path(sys.argv[9])
target_props_txt = pathlib.Path(sys.argv[10])
target_process_txt = pathlib.Path(sys.argv[11])
target_screenshot = pathlib.Path(sys.argv[12])
size_txt = pathlib.Path(sys.argv[13])
ocr_txt = pathlib.Path(sys.argv[14])
ocr_tsv = pathlib.Path(sys.argv[15])
source_manifest_copy = pathlib.Path(sys.argv[16])
source_windows_txt = pathlib.Path(sys.argv[17])
source_active_props_txt = pathlib.Path(sys.argv[18])
supporting_active_png = pathlib.Path(sys.argv[19])

selection = json.loads(selection_path.read_text(encoding="utf-8"))
windows_payload = json.loads(windows_json_path.read_text(encoding="utf-8"))
source_manifest = json.loads(source_manifest_copy.read_text(encoding="utf-8"))
target = selection["resolved_window"]
target_kind = selection["target_kind"]
requested = selection["requested"]
windows = windows_payload["windows"]


def read_text(path):
    if path.exists():
        return path.read_text(encoding="utf-8", errors="replace")
    return ""


def parse_desktops(text):
    entries = []
    current = None
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line:
            continue
        match = re.match(r"^(\d+)\s+([*-])\s+", line)
        if not match:
            continue
        desktop_id = int(match.group(1))
        is_current = match.group(2) == "*"
        entries.append({"desktop": desktop_id, "is_current": is_current, "raw": line})
        if is_current:
            current = desktop_id
    return current, entries


def parse_xprop(text):
    data = {"wm_class": [], "wm_name": "", "pid": ""}
    for line in text.splitlines():
        if line.startswith("WM_CLASS"):
            data["wm_class"] = re.findall(r'"([^"]+)"', line)
        elif line.startswith("WM_NAME"):
            matches = re.findall(r'"([^"]+)"', line)
            if matches:
                data["wm_name"] = matches[-1]
        elif "_NET_WM_PID" in line:
            match = re.search(r"=\s*(\d+)", line)
            if match:
                data["pid"] = match.group(1)
    return data


def parse_process(text):
    line = text.strip()
    if not line or line == "pid unavailable" or line.lower().startswith("error:"):
        return {"pid": "", "comm": "", "args": ""}
    parts = line.split(None, 2)
    return {
        "pid": parts[0] if len(parts) > 0 else "",
        "comm": parts[1] if len(parts) > 1 else "",
        "args": parts[2] if len(parts) > 2 else "",
    }


def app_name(props, process, title):
    tokens = " ".join(props.get("wm_class", []) + [process.get("comm", ""), process.get("args", ""), title or ""]).lower()
    mapping = [
        ("chatgpt", "ChatGPT"),
        ("code", "Visual Studio Code"),
        ("visual studio code", "Visual Studio Code"),
        ("google-chrome", "Google Chrome"),
        ("chromium", "Chromium"),
        ("firefox", "Firefox"),
        ("xmessage", "XMessage"),
        ("zenity", "Zenity"),
        ("gnome-terminal", "GNOME Terminal"),
        ("xterm", "XTerm"),
        ("kitty", "Kitty"),
        ("alacritty", "Alacritty"),
        ("tilix", "Tilix"),
        ("konsole", "Konsole"),
    ]
    for needle, label in mapping:
        if needle in tokens:
            return label
    for value in reversed(props.get("wm_class", [])):
        if value:
            return value
    if process.get("comm"):
        return process["comm"]
    if title:
        return title
    return "unknown-app"


def surface_kind(app, title, ocr_text):
    haystack = " ".join([app, title, ocr_text]).lower()
    if "chatgpt" in haystack:
        return "chat-assistant"
    if "visual studio code" in haystack or "code" in haystack:
        return "editor"
    if any(term in haystack for term in ["terminal", "xterm", "bash", "zsh", "fish", "kitty", "alacritty", "konsole", "tilix"]):
        return "terminal"
    if any(term in haystack for term in ["xmessage", "zenity", "dialog"]):
        return "dialog"
    if any(term in haystack for term in ["chrome", "chromium", "firefox", "browser"]):
        return "browser"
    return "generic-window"


def clean_ocr_lines(text):
    lines = []
    seen = set()
    for raw_line in text.replace("\f", "\n").splitlines():
        line = re.sub(r"\s+", " ", raw_line).strip()
        if len(line) < 3:
            continue
        normalized = line.lower()
        if normalized in seen:
            continue
        seen.add(normalized)
        lines.append(line)
    return lines


def parse_ocr_confidence(path):
    if not path.exists():
        return {"words": 0, "avg_conf": None}
    words = []
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            text = (row.get("text") or "").strip()
            if not text:
                continue
            try:
                conf = float(row.get("conf") or "-1")
            except ValueError:
                continue
            if conf >= 0:
                words.append(conf)
    return {
        "words": len(words),
        "avg_conf": round(statistics.mean(words), 1) if words else None,
    }


def describe_visible_content(kind, app, title, lines):
    lower_lines = [line.lower() for line in lines]
    combined = "\n".join(lines).lower()
    if not lines:
        if kind == "desktop":
            return "The desktop screenshot is real, but OCR did not recover enough readable text to describe the visible content beyond window metadata."
        return "The window screenshot is real, but OCR did not recover enough readable text to describe the visible content confidently."

    snippets = ", ".join(f'"{line}"' for line in lines[:3])
    if "chatgpt" in combined or "chatgpt" in title.lower():
        if any(marker in combined for marker in ["##", "###", "nuevo chat", "biblioteca", "pregunta lo que quieras"]):
            return f'The visible content appears to be a ChatGPT conversation or workspace with sidebar/navigation text and a markdown-style checklist; OCR snippets include {snippets}.'
        return f'The visible content appears to be a ChatGPT conversation or workspace; OCR snippets include {snippets}.'
    if kind == "dialog":
        return f'The visible content appears to be a dialog/message window; OCR snippets include {snippets}.'
    if kind == "terminal":
        return f'The visible content appears to be a terminal session; OCR snippets include {snippets}.'
    if kind == "editor":
        return f'The visible content appears to be an editor/workspace window; OCR snippets include {snippets}.'
    if kind == "browser":
        return f'The visible content appears to be a browser page or web app; OCR snippets include {snippets}.'
    return f'The visible content looks text-heavy, but the app-specific semantics remain approximate; OCR snippets include {snippets}.'


def summarize_windows(items):
    summarized = []
    for item in items[:5]:
        title = item.get("title") or "(untitled)"
        summarized.append(
            {
                "window_id": item.get("window_id"),
                "desktop": item.get("desktop"),
                "title": title,
                "pid": item.get("pid"),
            }
        )
    return summarized


current_desktop, desktops = parse_desktops(read_text(desktops_txt))
target_props = parse_xprop(read_text(target_props_txt))
process_info = parse_process(read_text(target_process_txt))
ocr_text = read_text(ocr_txt)
ocr_lines = clean_ocr_lines(ocr_text)
ocr_confidence = parse_ocr_confidence(ocr_tsv)
title = target_props.get("wm_name") or target.get("title") or ""
app = app_name(target_props, process_info, title)
kind = surface_kind(app, title, ocr_text)
dimensions = read_text(size_txt).strip()
resolved_pid = target.get("pid")
if resolved_pid in {"", "0", None}:
    resolved_pid = target_props.get("pid") or process_info.get("pid") or ""

current_desktop_windows = []
if current_desktop is not None:
    for item in windows:
        desktop = item.get("desktop")
        if desktop == "-1":
            current_desktop_windows.append(item)
        else:
            try:
                if int(desktop) == current_desktop:
                    current_desktop_windows.append(item)
            except (TypeError, ValueError):
                continue

registered_current_desktop = [
    item for item in current_desktop_windows if item.get("title") and item.get("title") != "Desktop Icons 1"
]

claims = []
limits = []

window_identity = f'{app} window "{title or target.get("title") or "(untitled)"}"'

if target_kind == "desktop":
    claims.append(
        {
            "confidence": "high",
            "sources": ["window_metadata"],
            "text": f'The active surface registered by metadata is {window_identity} (window_id={target.get("window_id") or "unknown"}, pid={resolved_pid or "unknown"}).',
        }
    )
    if current_desktop is not None and registered_current_desktop:
        titles = ", ".join(f'"{item["title"]}"' for item in registered_current_desktop[:5])
        claims.append(
            {
                "confidence": "medium",
                "sources": ["window_metadata"],
                "text": f'Window metadata registers {len(registered_current_desktop)} titled surfaces on current desktop {current_desktop}: {titles}. This list is auditable metadata, not a guarantee that every listed window is unobscured in the screenshot.',
            }
        )
    claims.append(
        {
            "confidence": "medium" if ocr_lines else "low",
            "sources": ["desktop_screenshot", "ocr"],
            "text": describe_visible_content("desktop", app, title, ocr_lines[:6]),
        }
    )
    limits.append("Window metadata can confirm registered surfaces on the current desktop, but it does not prove whether a window is hidden behind another one.")
    limits.append("OCR is approximate and may miss stylized text, icons, or non-text content in the desktop screenshot.")
else:
    claims.append(
        {
            "confidence": "high",
            "sources": ["window_metadata"],
            "text": f'The described target resolves to {window_identity} (window_id={target.get("window_id") or "unknown"}, pid={resolved_pid or "unknown"}).',
        }
    )
    claims.append(
        {
            "confidence": "medium" if ocr_lines else "low",
            "sources": ["target_screenshot", "ocr"],
            "text": describe_visible_content(kind, app, title, ocr_lines[:6]),
        }
    )
    limits.append("OCR is approximate and may distort punctuation, sidebars, or small UI text.")
    limits.append("The description only covers the captured target window, not hidden tabs, background windows, or content outside the frame.")

summary = " ".join(claim["text"] for claim in claims[:2])
if target_kind == "desktop" and len(claims) > 2:
    summary = " ".join(claim["text"] for claim in claims[:3])

description = {
    "summary": summary,
    "claims": claims,
    "target_kind": target_kind,
    "target_window": {
        "window_id": target.get("window_id"),
        "title": title or target.get("title"),
        "pid": resolved_pid,
        "app": app,
        "surface_kind": kind,
        "is_active": bool(target.get("is_active")),
    },
    "selection_reason": selection.get("selection_reason"),
    "matched_window_count": selection.get("matched_window_count"),
    "requested": requested,
    "current_desktop": current_desktop,
    "registered_current_desktop_windows": summarize_windows(registered_current_desktop),
    "ocr_excerpt": ocr_lines[:8],
    "ocr": {
        "words_with_confidence": ocr_confidence["words"],
        "average_confidence": ocr_confidence["avg_conf"],
        "approximate": True,
    },
    "limits": limits,
}

sources = {
    "used": [
        {
            "id": "window_metadata",
            "kind": "metadata",
            "paths": [
                str(source_windows_txt),
                str(desktops_txt),
                str(target_props_txt),
                str(target_process_txt),
                str(source_active_props_txt),
            ],
            "role": "window identity, current desktop inventory, pid, and app hints",
            "certainty": "high",
        },
        {
            "id": "desktop_screenshot" if target_kind == "desktop" else "target_screenshot",
            "kind": "screenshot",
            "paths": [str(target_screenshot)],
            "role": "raw visual evidence for the described target",
            "certainty": "high",
        },
        {
            "id": "ocr",
            "kind": "ocr",
            "paths": [str(ocr_txt), str(ocr_tsv)],
            "role": "approximate text extraction from the screenshot",
            "certainty": "medium" if ocr_lines else "low",
            "notes": "OCR is approximate and should not be treated as perfect transcription.",
        },
    ],
    "supporting": [
        {
            "id": "source_perceive_manifest",
            "kind": "manifest",
            "paths": [str(source_manifest_copy)],
            "role": "links the semantic run back to the raw host perception capture",
        }
    ],
}
if supporting_active_png.exists():
    sources["supporting"].append(
        {
            "id": "supporting_active_window_screenshot",
            "kind": "screenshot",
            "paths": [str(supporting_active_png)],
            "role": "zoomed active-window screenshot captured by the raw perception lane",
        }
    )

artifacts = {
    "summary": str(summary_path),
    "description": str(description_path),
    "sources": str(sources_path),
    "selection": str(selection_path),
    "target_screenshot": str(target_screenshot),
    "windows": str(source_windows_txt),
    "windows_json": str(windows_json_path),
    "desktops": str(desktops_txt),
    "root_properties": str(root_props_txt),
    "target_window_properties": str(target_props_txt),
    "target_process": str(target_process_txt),
    "ocr_text": str(ocr_txt),
    "ocr_tsv": str(ocr_tsv),
    "source_perceive_manifest": str(source_manifest_copy),
}
if source_active_props_txt.exists():
    artifacts["active_window_properties"] = str(source_active_props_txt)
if supporting_active_png.exists():
    artifacts["supporting_active_window_screenshot"] = str(supporting_active_png)

manifest = {
    "kind": "golem_host_describe",
    "run_dir": str(run_dir),
    "target": {
        "kind": target_kind,
        "requested": requested,
        "selection_reason": selection.get("selection_reason"),
        "matched_window_count": selection.get("matched_window_count"),
        "resolved_window": description["target_window"],
    },
    "source_perceive_run_dir": source_manifest.get("run_dir"),
    "sources_used": [item["id"] for item in sources["used"]],
    "artifacts": artifacts,
    "description": description,
    "current_desktop": current_desktop,
    "registered_current_desktop_windows": description["registered_current_desktop_windows"],
    "ocr": description["ocr"],
}

description_path.write_text(json.dumps(description, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
sources_path.write_text(json.dumps(sources, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

summary_lines = [
    "GOLEM HOST SEMANTIC DESCRIPTION",
    "",
    f"run_dir: {run_dir}",
    f"target: {target_kind}",
    f"requested_window_id: {requested.get('window_id') or '(none)'}",
    f"requested_title: {requested.get('title') or '(none)'}",
    f"selection_reason: {selection.get('selection_reason')}",
    f"matched_window_count: {selection.get('matched_window_count')}",
    f"target_window_id: {description['target_window']['window_id'] or '(none)'}",
    f"target_title: {description['target_window']['title'] or '(none)'}",
    f"target_app: {description['target_window']['app']}",
    f"target_surface_kind: {description['target_window']['surface_kind']}",
    f"target_screenshot: {target_screenshot}",
    f"target_screenshot_size: {dimensions or '(unknown)'}",
    "sources_used:",
]
summary_lines.extend(f"- {item['id']}: {item['role']}" for item in sources["used"])
summary_lines.append("claims:")
summary_lines.extend(
    f"- [{'+'.join(claim['sources'])}/{claim['confidence']}] {claim['text']}"
    for claim in claims
)
summary_lines.append("ocr_excerpt:")
summary_lines.extend(f"- {line}" for line in description["ocr_excerpt"] or ["(none)"])
summary_lines.append("limits:")
summary_lines.extend(f"- {line}" for line in limits)
summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
PY

  emit_run "$format" "$run_dir"
}

main "$@"
