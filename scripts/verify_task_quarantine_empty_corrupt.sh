#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TMP_TASK_A="tasks/task-verify-empty-corrupt-a.json"
TMP_TASK_B="tasks/task-verify-empty-corrupt-b.json"
TMP_PATHS="diagnostics/task_audit/corrupt_paths.txt"
TMP_MANIFEST="diagnostics/task_audit/corrupt_quarantine_manifest.txt"
TMP_DEST_A="tasks/quarantine/corrupt_empty/$(basename "$TMP_TASK_A")"
TMP_DEST_B="tasks/quarantine/corrupt_empty/$(basename "$TMP_TASK_B")"
BACKUP_PATHS="$(mktemp)"
BACKUP_MANIFEST="$(mktemp)"
HAD_PATHS=0
HAD_MANIFEST=0

cleanup() {
  if [[ "$HAD_PATHS" == "1" && -f "$BACKUP_PATHS" ]]; then
    cp "$BACKUP_PATHS" "$TMP_PATHS"
  else
    rm -f "$TMP_PATHS"
  fi
  if [[ "$HAD_MANIFEST" == "1" && -f "$BACKUP_MANIFEST" ]]; then
    cp "$BACKUP_MANIFEST" "$TMP_MANIFEST"
  else
    rm -f "$TMP_MANIFEST"
  fi
  rm -f "$BACKUP_PATHS" "$BACKUP_MANIFEST"
  rm -f "$TMP_TASK_A" "$TMP_TASK_B" "$TMP_DEST_A" "$TMP_DEST_B"
}
trap cleanup EXIT

mkdir -p tasks/quarantine/corrupt_empty diagnostics/task_audit

if [[ -f "$TMP_PATHS" ]]; then
  HAD_PATHS=1
  cp "$TMP_PATHS" "$BACKUP_PATHS"
fi
if [[ -f "$TMP_MANIFEST" ]]; then
  HAD_MANIFEST=1
  cp "$TMP_MANIFEST" "$BACKUP_MANIFEST"
fi

: > "$TMP_TASK_A"
: > "$TMP_TASK_B"

cat > "$TMP_PATHS" <<EOF2
$TMP_TASK_A
$TMP_TASK_B
EOF2

OUT="$(./scripts/task_quarantine_empty_corrupt.sh)"

echo "$OUT" | grep -q "TASK_QUARANTINED $TMP_TASK_A -> $TMP_DEST_A" || {
  echo "FAIL: first quarantine line missing"
  exit 1
}
echo "$OUT" | grep -q "TASK_QUARANTINED $TMP_TASK_B -> $TMP_DEST_B" || {
  echo "FAIL: second quarantine line missing"
  exit 1
}
echo "$OUT" | grep -q "^QUARANTINE_SUMMARY moved=2 manifest=$TMP_MANIFEST$" || {
  echo "FAIL: quarantine summary mismatch"
  exit 1
}

[[ ! -e "$TMP_TASK_A" ]] || { echo "FAIL: source A still exists"; exit 1; }
[[ ! -e "$TMP_TASK_B" ]] || { echo "FAIL: source B still exists"; exit 1; }
[[ -e "$TMP_DEST_A" ]] || { echo "FAIL: dest A missing"; exit 1; }
[[ -e "$TMP_DEST_B" ]] || { echo "FAIL: dest B missing"; exit 1; }

grep -q "^QUARANTINED|$TMP_TASK_A|0|empty-corrupt-json|$TMP_DEST_A$" "$TMP_MANIFEST" || {
  echo "FAIL: manifest missing entry A"
  exit 1
}
grep -q "^QUARANTINED|$TMP_TASK_B|0|empty-corrupt-json|$TMP_DEST_B$" "$TMP_MANIFEST" || {
  echo "FAIL: manifest missing entry B"
  exit 1
}

echo "VERIFY_TASK_QUARANTINE_EMPTY_CORRUPT_OK"
