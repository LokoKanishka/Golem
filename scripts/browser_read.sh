#!/usr/bin/env bash
set -euo pipefail

PROFILE="chrome"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_read.sh snapshot
  ./scripts/browser_read.sh find <texto>
USAGE
}

ensure_tabs() {
  local tabs_raw
  tabs_raw="$(openclaw browser --browser-profile "$PROFILE" tabs 2>&1 || true)"
  if printf '%s' "$tabs_raw" | grep -q 'No tabs'; then
    echo "ERROR: no hay tabs adjuntas al perfil $PROFILE"
    echo "Adjuntá una pestaña con OpenClaw Browser Relay (badge ON) y volvé a probar."
    exit 1
  fi
}

snapshot_tmp() {
  local tmp
  tmp="$(mktemp)"
  openclaw browser --browser-profile "$PROFILE" snapshot > "$tmp"
  echo "$tmp"
}

cmd="${1:-}"

case "$cmd" in
  snapshot)
    ensure_tabs
    openclaw browser --browser-profile "$PROFILE" snapshot
    ;;
  find)
    query="${2:-}"
    if [ -z "$query" ]; then
      echo "ERROR: falta texto a buscar"
      usage
      exit 1
    fi

    ensure_tabs

    tmp_file="$(snapshot_tmp)"
    out_file="$(mktemp)"
    trap 'rm -f "$tmp_file" "$out_file"' EXIT

    if grep -Ein -C 2 -- "$query" "$tmp_file" > "$out_file"; then
      sed -n '1,160p' "$out_file"
    else
      echo "Sin coincidencias para: $query"
      exit 0
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
