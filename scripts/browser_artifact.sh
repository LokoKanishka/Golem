#!/usr/bin/env bash
set -euo pipefail

PROFILE="${GOLEM_BROWSER_PROFILE:-chrome}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_artifact.sh snapshot <slug>
  ./scripts/browser_artifact.sh find <slug> <texto>
USAGE
}

cleanup_files=()

cleanup() {
  if [ "${#cleanup_files[@]}" -eq 0 ]; then
    return
  fi
  rm -f "${cleanup_files[@]}"
}

trap cleanup EXIT

register_cleanup() {
  cleanup_files+=("$1")
}

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

ensure_tabs() {
  local tabs_raw
  if ! tabs_raw="$(openclaw browser --browser-profile "$PROFILE" tabs 2>&1)"; then
    printf '%s\n' "$tabs_raw" >&2
    fatal "no se pudo consultar tabs para el perfil $PROFILE"
  fi
  if printf '%s' "$tabs_raw" | grep -q 'No tabs'; then
    echo "ERROR: no hay tabs adjuntas al perfil $PROFILE" >&2
    echo "Adjuntá una pestaña con OpenClaw Browser Relay (badge ON) y volvé a probar." >&2
    exit 1
  fi
  if ! printf '%s\n' "$tabs_raw" | grep -Eq '^[0-9]+\.'; then
    printf '%s\n' "$tabs_raw" >&2
    fatal "no se pudo validar una tab adjunta para el perfil $PROFILE"
  fi
}

make_outbox() {
  mkdir -p "$OUTBOX_DIR"
}

artifact_file() {
  local slug="$1"
  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  echo "$OUTBOX_DIR/${ts}_${slug}.md"
}

display_path() {
  local file="$1"
  printf '%s\n' "${file#$REPO_ROOT/}"
}

write_header() {
  local file="$1" slug="$2"
  printf "# %s\n\n" "$slug" > "$file"
  printf "generated_at: %s\n" "$(date -u --iso-8601=seconds)" >> "$file"
  printf "profile: %s\n\n" "$PROFILE" >> "$file"
}

snapshot_output_valid() {
  local file="$1"
  if grep -Eiq '(^Error:|gateway closed|abnormal closure)' "$file"; then
    return 1
  fi
  if ! grep -Eq '^\s*[-0-9]+\.' "$file" && ! grep -Eq '^\s*-\s' "$file"; then
    return 1
  fi
}

capture_snapshot() {
  local tmp="$1"
  local raw
  if ! raw="$(openclaw browser --browser-profile "$PROFILE" snapshot 2>&1)"; then
    printf '%s\n' "$raw" >&2
    fatal "falló snapshot para el perfil $PROFILE"
  fi
  printf '%s\n' "$raw" > "$tmp"
  if ! snapshot_output_valid "$tmp"; then
    printf '%s\n' "$raw" >&2
    fatal "snapshot inválido para el perfil $PROFILE"
  fi
}

publish_artifact() {
  local tmp="$1" dest="$2"
  mv "$tmp" "$dest"
  chmod 664 "$dest"
  cleanup_files=("${cleanup_files[@]/$tmp}")
  echo "ARTIFACT_OK $(display_path "$dest")"
}

cmd="${1:-}"

case "$cmd" in
  snapshot)
    slug="${2:-}"
    if [ -z "$slug" ]; then
      echo "ERROR: falta slug" >&2
      usage
      exit 1
    fi
    make_outbox
    ensure_tabs
    out_file="$(artifact_file "$slug")"
    tmp_file="$(mktemp)"
    snapshot_file="$(mktemp)"
    register_cleanup "$tmp_file"
    register_cleanup "$snapshot_file"
    write_header "$tmp_file" "$slug"
    capture_snapshot "$snapshot_file"
    cat "$snapshot_file" >> "$tmp_file"
    publish_artifact "$tmp_file" "$out_file"
    ;;
  find)
    slug="${2:-}"
    query="${3:-}"
    if [ -z "$slug" ] || [ -z "$query" ]; then
      echo "ERROR: falta slug o texto a buscar" >&2
      usage
      exit 1
    fi
    make_outbox
    ensure_tabs
    out_file="$(artifact_file "$slug")"
    tmp_file="$(mktemp)"
    snapshot_file="$(mktemp)"
    matches_file="$(mktemp)"
    register_cleanup "$tmp_file"
    register_cleanup "$snapshot_file"
    register_cleanup "$matches_file"
    write_header "$tmp_file" "$slug"
    printf "query: %s\n\n" "$query" >> "$tmp_file"

    capture_snapshot "$snapshot_file"
    if grep -Ein -C 2 -- "$query" "$snapshot_file" > "$matches_file"; then
      cat "$matches_file" >> "$tmp_file"
    else
      printf "Sin coincidencias para: %s\n" "$query" >> "$tmp_file"
    fi
    publish_artifact "$tmp_file" "$out_file"
    ;;
  *)
    usage
    exit 1
    ;;
esac
