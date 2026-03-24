#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
title="Golem Host Describe Smoke $$"
dialog_pid=""
window_id=""

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
  if [[ -n "$window_id" ]]; then
    wmctrl -i -c "$window_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$dialog_pid" ]] && kill -0 "$dialog_pid" 2>/dev/null; then
    kill "$dialog_pid" 2>/dev/null || true
    wait "$dialog_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

open_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh open --label semantic-describe-dialog -- \
    xmessage -center -title "$title" "Semantic describe smoke\nSources must stay explicit" --json
)"

wait_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_act.sh wait-window --title "$title" --timeout 10 --json
)"

window_meta="$(python3 - "$open_json" "$wait_json" <<'PY'
import json
import sys
open_payload = json.loads(sys.argv[1])
wait_payload = json.loads(sys.argv[2])
print(open_payload["pid"])
print(wait_payload["window"]["window_id"])
PY
)"
dialog_pid="$(printf '%s\n' "$window_meta" | sed -n '1p')"
window_id="$(printf '%s\n' "$window_meta" | sed -n '2p')"

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

window_json="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_describe.sh window --title "$title" --json
)"

python3 - "$active_json" "$desktop_json" "$window_json" "$title" <<'PY'
import json
import pathlib
import sys

active_payload = json.loads(sys.argv[1])
desktop_payload = json.loads(sys.argv[2])
window_payload = json.loads(sys.argv[3])
title = sys.argv[4]

for payload in (active_payload, desktop_payload, window_payload):
    assert payload["kind"] == "golem_host_describe", payload["kind"]
    assert payload["artifacts"]["target_screenshot"], payload
    assert payload["artifacts"]["windows"], payload
    assert payload["artifacts"]["description"], payload
    assert payload["artifacts"]["sources"], payload
    expected_sources = {
        "window_metadata",
        "desktop_screenshot" if payload["target"]["kind"] == "desktop" else "target_screenshot",
        "ocr_raw",
        "ocr_enhanced",
        "ocr_normalized",
        "layout_heuristics",
        "surface_classification_heuristics",
        "structured_fields_heuristics",
    }
    assert expected_sources.issubset(set(payload["sources_used"])), payload["sources_used"]
    assert payload["description"]["claims"], payload
    assert payload["description"]["limits"], payload
    assert payload["description"]["summary"], payload
    assert payload["description"]["layout"]["sections"], payload["description"]["layout"]
    assert payload["description"]["surface_classification"]["category"], payload["description"]["surface_classification"]
    assert payload["description"]["useful_lines"], payload["description"]["useful_lines"]
    assert payload["description"]["useful_regions"], payload["description"]["useful_regions"]
    assert payload["description"]["structured_fields"]["category"] == payload["description"]["surface_classification"]["category"], payload["description"]["structured_fields"]
    assert "fine_fields" in payload["description"]["structured_fields"], payload["description"]["structured_fields"]
    assert "attempted_fine_fields" in payload["description"]["structured_fields"], payload["description"]["structured_fields"]
    assert payload["description"]["readable_text"]["normalized_excerpt"], payload["description"]["readable_text"]
    assert payload["description"]["source_breakdown"]["layout_heuristics"], payload["description"]["source_breakdown"]
    assert payload["description"]["source_breakdown"]["surface_classification_heuristics"], payload["description"]["source_breakdown"]
    assert payload["description"]["source_breakdown"]["structured_fields_heuristics"], payload["description"]["source_breakdown"]
    for key in ("target_screenshot", "windows", "description", "sources", "ocr_text", "ocr_tsv", "ocr_enhanced_image", "ocr_enhanced_text", "ocr_enhanced_tsv", "ocr_normalized_text", "layout", "surface_profile", "structured_fields"):
        path = pathlib.Path(payload["artifacts"][key])
        assert path.exists(), path
        assert path.stat().st_size > 0, path

assert active_payload["target"]["kind"] == "active-window"
assert desktop_payload["target"]["kind"] == "desktop"
assert window_payload["target"]["kind"] == "window"

assert title in active_payload["description"]["target_window"]["title"], active_payload["description"]["target_window"]
assert window_payload["target"]["resolved_window"]["title"] == title, window_payload["target"]["resolved_window"]
assert window_payload["target"]["matched_window_count"] >= 1

active_sources = pathlib.Path(active_payload["artifacts"]["sources"]).read_text(encoding="utf-8")
desktop_summary = pathlib.Path(desktop_payload["artifacts"]["summary"]).read_text(encoding="utf-8")
window_description = pathlib.Path(window_payload["artifacts"]["description"]).read_text(encoding="utf-8")
window_layout = pathlib.Path(window_payload["artifacts"]["layout"]).read_text(encoding="utf-8")
window_normalized_ocr = pathlib.Path(window_payload["artifacts"]["ocr_normalized_text"]).read_text(encoding="utf-8")
window_summary = pathlib.Path(window_payload["artifacts"]["summary"]).read_text(encoding="utf-8")

assert '"id": "window_metadata"' in active_sources
assert '"id": "ocr_raw"' in active_sources
assert '"id": "ocr_normalized"' in active_sources
assert '"id": "layout_heuristics"' in active_sources
assert '"id": "surface_classification_heuristics"' in active_sources
assert '"id": "structured_fields_heuristics"' in active_sources
assert "sources_used:" in desktop_summary
assert title in window_description
assert '"role": "header"' in window_layout or '"role": "main_content"' in window_layout or '"role": "footer"' in window_layout
assert "Semantic describe smoke" in window_normalized_ocr or "Sources must stay explicit" in window_normalized_ocr
assert "fine_fields:" in window_summary

print("SMOKE_HOST_DESCRIBE_LANE_OK")
print(f"HOST_DESCRIBE_ACTIVE_SUMMARY {active_payload['description']['summary']}")
print(f"HOST_DESCRIBE_DESKTOP_RUN_DIR {desktop_payload['run_dir']}")
print(f"HOST_DESCRIBE_WINDOW_RUN_DIR {window_payload['run_dir']}")
PY
