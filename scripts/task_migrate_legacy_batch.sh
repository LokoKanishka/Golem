#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LABEL=""
COUNT=""
ACTOR="system"
SCAN_FILE="diagnostics/task_audit/active_scan.txt"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_migrate_legacy_batch.sh --label <label> --count <n> [--actor <actor>] [--scan-file <path>]

Example:
./scripts/task_migrate_legacy_batch.sh --label batch_03 --count 50 --actor system
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      [[ $# -ge 2 ]] || usage
      LABEL="$2"
      shift 2
      ;;
    --count)
      [[ $# -ge 2 ]] || usage
      COUNT="$2"
      shift 2
      ;;
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
    --scan-file)
      [[ $# -ge 2 ]] || usage
      SCAN_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$LABEL" ]] || usage
[[ -n "$COUNT" ]] || usage
[[ "$COUNT" =~ ^[0-9]+$ ]] || {
  echo "Invalid count: $COUNT" >&2
  exit 2
}
[[ -f "$SCAN_FILE" ]] || {
  echo "Missing scan file: $SCAN_FILE" >&2
  exit 2
}

CANDIDATES="diagnostics/task_audit/legacy_${LABEL}_candidates.txt"
DRY_RUN_OUT="diagnostics/task_audit/legacy_${LABEL}_dry_run.txt"
MIGRATED_OUT="diagnostics/task_audit/legacy_${LABEL}_migrated.txt"
VALIDATE_OUT="diagnostics/task_audit/legacy_${LABEL}_validate.txt"

python3 - "$SCAN_FILE" "$CANDIDATES" "$COUNT" <<'PY'
import pathlib
import sys

scan_file = pathlib.Path(sys.argv[1])
candidates_out = pathlib.Path(sys.argv[2])
count = int(sys.argv[3])

lines = scan_file.read_text(encoding="utf-8").splitlines()
legacy_paths = []

for line in lines:
    if line.startswith("TASK_SCAN_LEGACY "):
        parts = line.split()
        if len(parts) >= 3:
            legacy_paths.append(parts[-1])

selected = legacy_paths[:count]
candidates_out.write_text("\n".join(selected) + ("\n" if selected else ""), encoding="utf-8")

print(f"LEGACY_BATCH_SELECTED {len(selected)}")
for item in selected:
    print(item)
PY

SELECTED="$(grep -c . "$CANDIDATES" || true)"
[[ "$SELECTED" -gt 0 ]] || {
  echo "No legacy candidates found." >&2
  exit 3
}

: > "$DRY_RUN_OUT"
while IFS= read -r task_path; do
  [[ -n "${task_path// }" ]] || continue
  ./scripts/task_migrate_legacy.sh "$task_path" --actor "$ACTOR" --dry-run >> "$DRY_RUN_OUT"
done < "$CANDIDATES"

: > "$MIGRATED_OUT"
: > "$VALIDATE_OUT"

while IFS= read -r task_path; do
  [[ -n "${task_path// }" ]] || continue

  migrate_tmp="$(mktemp)"
  ./scripts/task_migrate_legacy.sh "$task_path" --actor "$ACTOR" | tee -a "$MIGRATED_OUT" > "$migrate_tmp"

  migrated_path="$(tail -n 1 "$migrate_tmp")"
  rm -f "$migrate_tmp"

  [[ -f "$migrated_path" ]] || {
    echo "Migrated path not found: $migrated_path" >&2
    exit 4
  }

  ./scripts/task_validate.sh "$migrated_path" --strict >> "$VALIDATE_OUT"
done < "$CANDIDATES"

echo "LEGACY_BATCH_DONE label=$LABEL count=$SELECTED actor=$ACTOR"
