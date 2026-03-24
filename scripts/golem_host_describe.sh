#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/golem_host_capability_common.sh
source "${SCRIPT_DIR}/golem_host_capability_common.sh"

SCREENSHOT_HELPER="${GOLEM_SCREENSHOT_HELPER:-$HOME/.codex/skills/screenshot/scripts/take_screenshot.py}"
DESCRIBE_ANALYZE_HELPER="${GOLEM_HOST_DESCRIBE_ANALYZE_HELPER:-${SCRIPT_DIR}/golem_host_describe_analyze.py}"

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
  GOLEM_HOST_DESCRIBE_ANALYZE_HELPER
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

  golem_host_capabilities_require_tools python3 wmctrl xdotool xprop identify convert tesseract ps
  [ -f "$SCREENSHOT_HELPER" ] || {
    printf 'ERROR: screenshot helper not found: %s\n' "$SCREENSHOT_HELPER" >&2
    exit 1
  }
  [ -f "$DESCRIBE_ANALYZE_HELPER" ] || {
    printf 'ERROR: describe analyze helper not found: %s\n' "$DESCRIBE_ANALYZE_HELPER" >&2
    exit 1
  }

  local perceive_json run_dir summary_path manifest_path description_path sources_path
  local selection_path windows_json_path desktops_txt root_props_txt target_props_txt target_process_txt
  local source_manifest_copy source_windows_txt source_active_props_txt target_screenshot size_txt
  local ocr_txt ocr_tsv ocr_enhanced_png ocr_enhanced_txt ocr_enhanced_tsv ocr_normalized_txt layout_json supporting_active_png
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
  ocr_enhanced_png="${run_dir}/ocr-enhanced.png"
  ocr_enhanced_txt="${run_dir}/ocr-enhanced.txt"
  ocr_enhanced_tsv="${run_dir}/ocr-enhanced.tsv"
  ocr_normalized_txt="${run_dir}/ocr-normalized.txt"
  layout_json="${run_dir}/layout.json"

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

  if ! convert "$target_screenshot" \
    -colorspace Gray \
    -strip \
    -filter Lanczos \
    -resize 200% \
    -contrast-stretch 1%x1% \
    -sharpen 0x1 \
    "$ocr_enhanced_png" >/dev/null 2>&1; then
    cp "$target_screenshot" "$ocr_enhanced_png"
  fi

  tesseract "$ocr_enhanced_png" "${run_dir}/ocr-enhanced" --psm 11 >/dev/null 2>&1 || true
  [ -f "$ocr_enhanced_txt" ] || : >"$ocr_enhanced_txt"
  tesseract "$ocr_enhanced_png" "${run_dir}/ocr-enhanced" --psm 11 tsv >/dev/null 2>&1 || true
  if [ -f "${run_dir}/ocr-enhanced.tsv" ] && [ "${run_dir}/ocr-enhanced.tsv" != "$ocr_enhanced_tsv" ]; then
    mv "${run_dir}/ocr-enhanced.tsv" "$ocr_enhanced_tsv"
  elif [ -f "${run_dir}/ocr-enhanced.txt.tsv" ]; then
    mv "${run_dir}/ocr-enhanced.txt.tsv" "$ocr_enhanced_tsv"
  elif [ -f "${run_dir}/ocr-enhanced.tsv.txt" ]; then
    mv "${run_dir}/ocr-enhanced.tsv.txt" "$ocr_enhanced_tsv"
  else
    printf 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n' >"$ocr_enhanced_tsv"
  fi

  python3 "$DESCRIBE_ANALYZE_HELPER" \
    --run-dir "$run_dir" \
    --summary-path "$summary_path" \
    --manifest-path "$manifest_path" \
    --description-path "$description_path" \
    --sources-path "$sources_path" \
    --selection-path "$selection_path" \
    --windows-json-path "$windows_json_path" \
    --desktops-path "$desktops_txt" \
    --root-props-path "$root_props_txt" \
    --target-props-path "$target_props_txt" \
    --target-process-path "$target_process_txt" \
    --target-screenshot "$target_screenshot" \
    --size-path "$size_txt" \
    --ocr-text "$ocr_txt" \
    --ocr-tsv "$ocr_tsv" \
    --ocr-enhanced-image "$ocr_enhanced_png" \
    --ocr-enhanced-text "$ocr_enhanced_txt" \
    --ocr-enhanced-tsv "$ocr_enhanced_tsv" \
    --ocr-normalized-text "$ocr_normalized_txt" \
    --layout-path "$layout_json" \
    --source-perceive-manifest "$source_manifest_copy" \
    --source-windows "$source_windows_txt" \
    --source-active-props "$source_active_props_txt" \
    --supporting-active-png "$supporting_active_png"

  emit_run "$format" "$run_dir"
}

main "$@"
