#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/golem_browser_relay_common.sh"

exec node "$SCRIPT_DIR/golem_browser_relay_attach_tab.js" "$@"
