#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SCAN_FILE="diagnostics/task_audit/active_scan.txt"
CANDIDATES="diagnostics/task_audit/legacy_batch_01_candidates.txt"
DRY_RUN_OUT="diagnostics/task_audit/legacy_batch_01_dry_run.txt"
MIGRATED_OUT="diagnostics/task_audit/legacy_batch_01_migrated.txt"
VALIDATE_OUT="diagnostics/task_audit/legacy_batch_01_validate.txt"

[[ -f "$SCAN_FILE" ]] || {
  echo "Missing scan file: $SCAN_FILE" >&2
  exit 2
}

python3 - "$SCAN_FILE" "$CANDIDATES" <<'PY'
import pathlib
import sys

scan_file = pathlib.Path(sys.argv[1])
candidates_out = pathlib.Path(sys.argv[2])

lines = scan_file.read_text(encoding="utf-8").splitlines()
legacy_paths = []

for line in lines:
    if line.startswith("TASK_SCAN_LEGACY "):
        parts = line.split()
        if len(parts) >= 3:
            legacy_paths.append(parts[-1])

selected = legacy_paths[:10]
candidates_out.write_text("\n".join(selected) + ("\n" if selected else ""), encoding="utf-8")
print(f"LEGACY_BATCH_01_SELECTED {len(selected)}")
for item in selected:
    print(item)
PY

COUNT="$(grep -c . "$CANDIDATES" || true)"
[[ "$COUNT" -gt 0 ]] || {
  echo "No legacy candidates found for batch 01." >&2
  exit 3
}

: > "$DRY_RUN_OUT"
while IFS= read -r task_path; do
  [[ -n "${task_path// }" ]] || continue
  ./scripts/task_migrate_legacy.sh "$task_path" --actor system --dry-run >> "$DRY_RUN_OUT"
done < "$CANDIDATES"

: > "$MIGRATED_OUT"
: > "$VALIDATE_OUT"

while IFS= read -r task_path; do
  [[ -n "${task_path// }" ]] || continue

  MIGRATE_TMP="$(mktemp)"
  ./scripts/task_migrate_legacy.sh "$task_path" --actor system | tee -a "$MIGRATED_OUT" > "$MIGRATE_TMP"

  migrated_path="$(tail -n 1 "$MIGRATE_TMP")"
  rm -f "$MIGRATE_TMP"

  [[ -f "$migrated_path" ]] || {
    echo "Migrated path not found: $migrated_path" >&2
    exit 4
  }

  ./scripts/task_validate.sh "$migrated_path" --strict >> "$VALIDATE_OUT"
done < "$CANDIDATES"

echo "LEGACY_BATCH_01_DONE count=$COUNT"
