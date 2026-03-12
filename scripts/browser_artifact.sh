#!/usr/bin/env bash
set -euo pipefail

PROFILE="chrome"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_artifact.sh snapshot <slug>
  ./scripts/browser_artifact.sh find <slug> <texto>
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

make_outbox() {
  mkdir -p outbox/manual
}

artifact_file() {
  local slug="$1"
  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  echo "outbox/manual/${ts}_${slug}.md"
}

write_header() {
  local file="$1" slug="$2"
  printf "# %s\n\n" "$slug" > "$file"
  printf "generated_at: %s\n" "$(date -u --iso-8601=seconds)" >> "$file"
  printf "profile: %s\n\n" "$PROFILE" >> "$file"
}

snapshot_tmp() {
  local tmp
  tmp=$(mktemp)
  openclaw browser --browser-profile "$PROFILE" snapshot > "$tmp"
  echo "$tmp"
}

cmd="${1:-}"

case "$cmd" in
  snapshot)
    slug="${2:-}"
    if [ -z "$slug" ]; then
      echo "ERROR: falta slug"
      usage
      exit 1
    fi
    ensure_tabs
    make_outbox
    out_file=$(artifact_file "$slug")
    write_header "$out_file" "$slug"
    # append snapshot
    openclaw browser --browser-profile "$PROFILE" snapshot >> "$out_file"
    echo "ARTIFACT_OK $out_file"
    ;;
  find)
    slug="${2:-}"
    query="${3:-}"
    if [ -z "$slug" ] || [ -z "$query" ]; then
      echo "ERROR: falta slug o texto a buscar"
      usage
      exit 1
    fi
    ensure_tabs
    make_outbox
    out_file=$(artifact_file "$slug")
    write_header "$out_file" "$slug"
    printf "query: %s\n\n" "$query" >> "$out_file"

    tmp_file=$(snapshot_tmp)
    trap 'rm -f "$tmp_file"' EXIT
    if grep -Ein -C 2 -- "$query" "$tmp_file" > /dev/null; then
      grep -Ein -C 2 -- "$query" "$tmp_file" >> "$out_file"
    else
      printf "Sin coincidencias para: %s\n" "$query" >> "$out_file"
    fi
    echo "ARTIFACT_OK $out_file"
    ;;
  *)
    usage
    exit 1
    ;;
esac
