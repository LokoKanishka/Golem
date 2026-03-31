#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  printf 'Uso: ./scripts/browser_sidecar_select.sh [indice|titulo-parcial|url-parcial]\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

selector="${1:-}"

browser_sidecar_require_running

selection_json="$(browser_sidecar_resolve_selector_json "$selector")"

python3 - <<'PY' "$selection_json"
import json
import sys

payload = json.loads(sys.argv[1])
print(f'match_type: {payload.get("match_type", "")}')
print(f'index: {payload.get("index", "")}')
print(f'title: {payload.get("title", "")}')
print(f'url: {payload.get("url", "")}')
print(f'id: {payload.get("id", "")}')
PY
