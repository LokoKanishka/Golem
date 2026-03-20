#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MIGRATED_FILE="diagnostics/task_audit/legacy_batch_01_migrated.txt"
OUT_FILE="diagnostics/task_audit/legacy_batch_01_quality.txt"
BASELINE_DOC="docs/TASK_LEGACY_BASELINE_AUDIT.md"

[[ -f "$MIGRATED_FILE" ]] || {
  echo "Missing migrated file: $MIGRATED_FILE" >&2
  exit 2
}

python3 - "$MIGRATED_FILE" "$OUT_FILE" "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

migrated_file = pathlib.Path(sys.argv[1])
out_file = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3])

lines = migrated_file.read_text(encoding="utf-8").splitlines()
paths = []

for line in lines:
    stripped = line.strip()
    if not stripped:
        continue
    if stripped.endswith(".json"):
        candidate = pathlib.Path(stripped)
        if not candidate.is_absolute():
            candidate = repo_root / candidate
        if candidate.exists():
            paths.append(candidate)

# de-dup conservando orden
seen = set()
ordered = []
for p in paths:
    if str(p) not in seen:
        seen.add(str(p))
        ordered.append(p)
paths = ordered

report = []
report.append("# Legacy Batch 01 Quality Gate")
report.append("")
report.append(f"migrated_paths_detected={len(paths)}")
report.append("")

ok = 0
fail = 0

for path in paths:
    task_ok = True
    reasons = []

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        task_ok = False
        reasons.append(f"json-load-fail:{type(e).__name__}:{e}")
        data = None

    if data is not None:
        if data.get("id") != path.stem:
            task_ok = False
            reasons.append("id-filename-mismatch")

        if not isinstance(data.get("status"), str) or not data.get("status"):
            task_ok = False
            reasons.append("missing-status")

        if not isinstance(data.get("owner"), str) or not data.get("owner"):
            task_ok = False
            reasons.append("missing-owner")

        if not isinstance(data.get("source_channel"), str) or not data.get("source_channel"):
            task_ok = False
            reasons.append("missing-source-channel")

        if not isinstance(data.get("evidence"), list):
            task_ok = False
            reasons.append("evidence-not-list")

        if not isinstance(data.get("artifacts"), list):
            task_ok = False
            reasons.append("artifacts-not-list")

        if not isinstance(data.get("history"), list) or not data.get("history"):
            task_ok = False
            reasons.append("history-missing-or-empty")
        else:
            actions = [h.get("action") for h in data["history"] if isinstance(h, dict)]
            if "migrated_from_legacy" not in actions:
                task_ok = False
                reasons.append("missing-migrated_from_legacy")

        migration_evidence = []
        if isinstance(data.get("evidence"), list):
            migration_evidence = [
                e for e in data["evidence"]
                if isinstance(e, dict) and e.get("type") == "migration"
            ]
        if not migration_evidence:
            task_ok = False
            reasons.append("missing-migration-evidence")
        else:
            backup_rel = migration_evidence[-1].get("path")
            if not isinstance(backup_rel, str) or not backup_rel.strip():
                task_ok = False
                reasons.append("migration-evidence-missing-backup-path")
            else:
                backup_abs = repo_root / backup_rel
                if not backup_abs.exists():
                    task_ok = False
                    reasons.append(f"backup-missing:{backup_rel}")

    if task_ok:
        ok += 1
        report.append(f"OK|{path}")
    else:
        fail += 1
        joined = ";".join(reasons) if reasons else "unknown-failure"
        report.append(f"FAIL|{path}|{joined}")

report.append("")
report.append(f"QUALITY_SUMMARY total={len(paths)} ok={ok} fail={fail}")

out_file.write_text("\n".join(report) + "\n", encoding="utf-8")
print(out_file)
PY

while IFS= read -r line; do
  case "$line" in
    OK\|*)
      path="${line#OK|}"
      ./scripts/task_validate.sh "$path" --strict > /dev/null
      ;;
  esac
done < diagnostics/task_audit/legacy_batch_01_quality.txt

python3 - "$BASELINE_DOC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """## Next Step

La próxima acción correcta es seleccionar la primera tanda real de tratamiento:

1. revisar los `corrupt`;
2. decidir si se reparan o se aíslan;
3. luego migrar legacy simples en tandas chicas.
"""

new = """## Next Step

La próxima acción correcta es continuar con migración legacy controlada en tandas chicas,
porque el carril activo ya quedó sin `corrupt`.

Secuencia sugerida:

1. inspeccionar calidad de los primeros migrados;
2. si la quality gate sale limpia, abrir Batch 02;
3. seguir escalando por tandas pequeñas y auditables.
"""

if old in text:
    text = text.replace(old, new)

path.write_text(text, encoding="utf-8")
print(path)
PY

printf '\n== quality gate ==\n'
cat "$OUT_FILE"
