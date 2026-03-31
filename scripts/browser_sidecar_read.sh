#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  printf 'Uso: ./scripts/browser_sidecar_read.sh [indice|titulo-parcial|url-parcial|url]\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

target="${1:-}"
resolved_selector=""

browser_sidecar_require_running

if [ -n "$target" ] && browser_sidecar_looks_like_url "$target"; then
  browser_sidecar_run_tool open "$target" >/dev/null
  sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"
elif [ -n "$target" ]; then
  resolved_selector="$(browser_sidecar_resolve_selector_field "$target" index)"
fi

selection_json="$(browser_sidecar_resolve_selector_json "$resolved_selector")"

python3 - <<'PY' "$selection_json"
import json
import sys

payload = json.loads(sys.argv[1])
print("# Sidecar Read")
print(f'match_type: {payload.get("match_type", "")}')
print(f'index: {payload.get("index", "")}')
print(f'title: {payload.get("title", "")}')
print(f'url: {payload.get("url", "")}')
print(f'id: {payload.get("id", "")}')
print()
PY

if [ -n "$resolved_selector" ]; then
  browser_sidecar_run_tool snapshot "$resolved_selector"
else
  browser_sidecar_run_tool snapshot
fi
