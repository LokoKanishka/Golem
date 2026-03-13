#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/validate_markdown_artifact.sh <path>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

artifact_path_raw="${1:-}"
if [ -z "$artifact_path_raw" ]; then
  usage
  fatal "falta path"
fi

artifact_path="$artifact_path_raw"
if [ ! -e "$artifact_path" ]; then
  artifact_path="$REPO_ROOT/$artifact_path_raw"
fi

python3 - "$artifact_path" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1]).resolve()

if not path.exists():
    print(f"ERROR: no existe el archivo: {sys.argv[1]}", file=sys.stderr)
    raise SystemExit(1)

if path.suffix.lower() != ".md":
    print(f"ERROR: el archivo no es markdown (.md): {path}", file=sys.stderr)
    raise SystemExit(1)

text = path.read_text(encoding="utf-8", errors="replace")
if not text.strip():
    print(f"ERROR: el archivo markdown esta vacio: {path}", file=sys.stderr)
    raise SystemExit(1)

lines = text.splitlines()
non_empty = [line.rstrip() for line in lines if line.strip()]
if len(non_empty) < 4:
    print(f"ERROR: el markdown no tiene contenido suficiente: {path}", file=sys.stderr)
    raise SystemExit(1)

head_window = non_empty[:10]
if not any(line.startswith("# ") and len(line[2:].strip()) >= 3 for line in head_window):
    print(f"ERROR: falta H1 cerca del inicio: {path}", file=sys.stderr)
    raise SystemExit(1)

timestamp_pattern = re.compile(r"^(?:-\s+)?(generated_at|delegated_at|created_at):\s+\S+")
meta_window = non_empty[:40]
if not any(timestamp_pattern.match(line) for line in meta_window):
    print(f"ERROR: falta generated_at o equivalente documentado: {path}", file=sys.stderr)
    raise SystemExit(1)

trivial_prefixes = ("# ", "generated_at:", "delegated_at:", "created_at:", "repo:", "task_type:", "profile:", "task_id:", "artifact_kind:")
body_lines = []
for line in non_empty:
    if line.startswith("## "):
        body_lines.append(line)
        continue
    if line.startswith(trivial_prefixes):
        continue
    body_lines.append(line)

useful_chars = sum(len(line.strip()) for line in body_lines)
if useful_chars < 40:
    print(f"ERROR: el markdown no tiene contenido adicional no trivial: {path}", file=sys.stderr)
    raise SystemExit(1)

print(f"MARKDOWN_ARTIFACT_OK {path}")
PY
