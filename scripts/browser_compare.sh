#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_compare.sh files <slug> <file_a> <file_b>
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
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

make_outbox() {
  mkdir -p "$OUTBOX_DIR"
}

artifact_file() {
  local slug="$1"
  local ts
  ts="$(date -u +"%Y%m%dT%H%M%SZ")"
  printf '%s\n' "$OUTBOX_DIR/${ts}_${slug}.md"
}

display_path() {
  local file="$1"
  printf '%s\n' "${file#$REPO_ROOT/}"
}

validate_slug() {
  local slug="$1"
  if [ -z "$slug" ]; then
    fatal "falta slug"
  fi
  if [[ "$slug" == *"/"* ]]; then
    fatal "slug inválido: no puede contener /"
  fi
}

resolve_repo_file() {
  local input="$1"
  local resolved

  if ! resolved="$(realpath -e "$input" 2>/dev/null)"; then
    fatal "no existe el archivo: $input"
  fi
  if [ ! -f "$resolved" ]; then
    fatal "el input no es un archivo regular: $input"
  fi
  case "$resolved" in
    "$REPO_ROOT"/*) ;;
    *)
      fatal "el input queda fuera del repo: $input"
      ;;
  esac

  printf '%s\n' "$resolved"
}

publish_comparison() {
  local tmp="$1"
  local dest="$2"

  "$VALIDATE_MARKDOWN" "$tmp" >/dev/null
  mv "$tmp" "$dest"
  chmod 664 "$dest"
  cleanup_files=("${cleanup_files[@]/$tmp}")
  printf 'COMPARISON_OK %s\n' "$(display_path "$dest")"
}

cmd="${1:-}"

case "$cmd" in
  files)
    slug="${2:-}"
    input_a_raw="${3:-}"
    input_b_raw="${4:-}"

    validate_slug "$slug"
    if [ -z "$input_a_raw" ] || [ -z "$input_b_raw" ]; then
      fatal "faltan file_a o file_b"
    fi

    cd "$REPO_ROOT"
    make_outbox

    input_a="$(resolve_repo_file "$input_a_raw")"
    input_b="$(resolve_repo_file "$input_b_raw")"
    out_file="$(artifact_file "$slug")"
    tmp_file="$(mktemp "$OUTBOX_DIR/.comparison.XXXXXX.md")"
    register_cleanup "$tmp_file"

    python3 - "$slug" "$input_a" "$input_b" "$REPO_ROOT" > "$tmp_file" <<'PY'
import datetime
import pathlib
import sys

slug, input_a, input_b, repo_root = sys.argv[1:5]

repo_root_path = pathlib.Path(repo_root)
input_a_path = pathlib.Path(input_a)
input_b_path = pathlib.Path(input_b)

MAX_LINES = 60


def read_lines(path: pathlib.Path):
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def normalize(line: str) -> str:
    return " ".join(line.strip().split())


def unique_significant(lines):
    ordered = []
    seen = set()
    for line in lines:
        normalized = normalize(line)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        ordered.append(normalized)
    return ordered


def emit_section(title: str, items):
    print(f"## {title}")
    if not items:
        print("- (none)")
        print()
        return

    shown = items[:MAX_LINES]
    for item in shown:
        print(f"- {item}")
    if len(items) > MAX_LINES:
        print(f"- ... truncated, showing {MAX_LINES} of {len(items)} lines")
    print()


lines_a = read_lines(input_a_path)
lines_b = read_lines(input_b_path)
unique_a = unique_significant(lines_a)
unique_b = unique_significant(lines_b)

set_a = set(unique_a)
set_b = set(unique_b)

common = [line for line in unique_a if line in set_b]
only_a = [line for line in unique_a if line not in set_b]
only_b = [line for line in unique_b if line not in set_a]

generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
input_a_rel = input_a_path.relative_to(repo_root_path)
input_b_rel = input_b_path.relative_to(repo_root_path)

print(f"# {slug}")
print()
print(f"generated_at: {generated_at}")
print(f"repo: {repo_root}")
print("artifact_kind: compare-files")
print(f"input_a: {input_a_rel}")
print(f"input_b: {input_b_rel}")
print()
print("## Summary")
print(f"- lines_in_a: {len(lines_a)}")
print(f"- lines_in_b: {len(lines_b)}")
print(f"- common_significant_lines: {len(common)}")
print(f"- only_in_a: {len(only_a)}")
print(f"- only_in_b: {len(only_b)}")
print()

emit_section("Common lines", common)
emit_section("Only in A", only_a)
emit_section("Only in B", only_b)

print("## Notes")
print("- Comparacion textual simple basada en lineas normalizadas y no vacias.")
print("- No intenta inferir equivalencias semanticas, jerarquias ni cambios estructurales complejos.")
PY

    if [ ! -s "$tmp_file" ]; then
      fatal "no se pudo generar el reporte de comparación"
    fi

    publish_comparison "$tmp_file" "$out_file"
    ;;
  *)
    usage
    exit 1
    ;;
esac
