#!/usr/bin/env bash
set -euo pipefail

PROFILE="chrome"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_nav.sh tabs
  ./scripts/browser_nav.sh open <url>
  ./scripts/browser_nav.sh snapshot
USAGE
}

cmd="${1:-}"

case "$cmd" in
  tabs)
    openclaw browser --browser-profile "$PROFILE" tabs
    ;;
  open)
    url="${2:-}"
    if [ -z "$url" ]; then
      echo "ERROR: falta URL"
      usage
      exit 1
    fi
    case "$url" in
      http://*|https://*)
        openclaw browser --browser-profile "$PROFILE" open "$url"
        ;;
      *)
        echo "ERROR: la URL debe empezar con http:// o https://"
        exit 1
        ;;
    esac
    ;;
  snapshot)
    openclaw browser --browser-profile "$PROFILE" snapshot
    ;;
  *)
    usage
    exit 1
    ;;
esac
