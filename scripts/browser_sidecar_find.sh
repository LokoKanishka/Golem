#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'Uso: ./scripts/browser_sidecar_find.sh <texto> [selector|url]\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

query="$1"
target="${2:-}"
selector=""

browser_sidecar_require_running

if [ -n "$target" ] && browser_sidecar_looks_like_url "$target"; then
  browser_sidecar_run_tool open "$target" >/dev/null
  sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"
elif [ -n "$target" ]; then
  selector="$(browser_sidecar_resolve_selector_field "$target" index)"
fi

if [ -n "$selector" ]; then
  browser_sidecar_run_tool find "$query" "$selector"
else
  browser_sidecar_run_tool find "$query"
fi
