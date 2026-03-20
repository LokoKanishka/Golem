#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PATHS_FILE="diagnostics/task_audit/corrupt_paths.txt"
QUARANTINE_DIR="tasks/quarantine/corrupt_empty"
MANIFEST="diagnostics/task_audit/corrupt_quarantine_manifest.txt"

mkdir -p "$QUARANTINE_DIR"

[[ -f "$PATHS_FILE" ]] || {
  echo "Missing corrupt paths file: $PATHS_FILE" >&2
  exit 2
}

: > "$MANIFEST"

count=0
while IFS= read -r raw_path; do
  [[ -n "${raw_path// }" ]] || continue

  if [[ ! -e "$raw_path" ]]; then
    echo "MISSING|$raw_path||missing-path|not-moved" >> "$MANIFEST"
    echo "Missing corrupt path: $raw_path" >&2
    exit 3
  fi

  size="$(stat -c '%s' "$raw_path")"
  if [[ "$size" != "0" ]]; then
    echo "NONEMPTY|$raw_path|$size|expected-zero-byte|not-moved" >> "$MANIFEST"
    echo "Refusing to quarantine non-empty file: $raw_path ($size bytes)" >&2
    exit 4
  fi

  base="$(basename "$raw_path")"
  dest="$QUARANTINE_DIR/$base"

  if [[ -e "$dest" ]]; then
    echo "DEST_EXISTS|$raw_path|$size|destination-exists|$dest" >> "$MANIFEST"
    echo "Destination already exists: $dest" >&2
    exit 5
  fi

  mv "$raw_path" "$dest"
  echo "QUARANTINED|$raw_path|$size|empty-corrupt-json|$dest" >> "$MANIFEST"
  echo "TASK_QUARANTINED $raw_path -> $dest"
  count=$((count + 1))
done < "$PATHS_FILE"

echo "QUARANTINE_SUMMARY moved=$count manifest=$MANIFEST"
