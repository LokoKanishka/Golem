#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

target="${1:-}"
selector=""

browser_sidecar_require_running

if [ -n "$target" ] && browser_sidecar_looks_like_url "$target"; then
  browser_sidecar_run_tool open "$target" >/dev/null
  sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"
elif [ -n "$target" ]; then
  selector="$(browser_sidecar_resolve_selector_field "$target" index)"
fi

if [ -n "$selector" ]; then
  browser_sidecar_run_tool snapshot "$selector"
else
  browser_sidecar_run_tool snapshot
fi
