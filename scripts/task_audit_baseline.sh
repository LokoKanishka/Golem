#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="diagnostics/task_audit"
mkdir -p "$OUT_DIR"

ACTIVE_OUT="$OUT_DIR/active_scan.txt"
ARCHIVE_OUT="$OUT_DIR/archive_scan.txt"
COMBINED_OUT="$OUT_DIR/combined_scan.txt"
REPORT_OUT="docs/TASK_LEGACY_BASELINE_AUDIT.md"

./scripts/task_scan_legacy.sh --all > "$ACTIVE_OUT"
./scripts/task_scan_legacy.sh --all --include-archive > "$COMBINED_OUT"

if [[ -d tasks/archive ]]; then
  python3 - "$COMBINED_OUT" "$ARCHIVE_OUT" <<'PY'
import pathlib
import sys

combined = pathlib.Path(sys.argv[1])
archive_out = pathlib.Path(sys.argv[2])

lines = combined.read_text(encoding="utf-8").splitlines()
archive_lines = []
counts = {
    "TASK_SCAN_CANONICAL ": 0,
    "TASK_SCAN_LEGACY ": 0,
    "TASK_SCAN_CORRUPT ": 0,
    "TASK_SCAN_INVALID ": 0,
}
for line in lines:
    if "/tasks/archive/" in line:
        archive_lines.append(line)
        for prefix in counts:
            if line.startswith(prefix):
                counts[prefix] += 1
                break

summary = (
    f"SCAN_SUMMARY total={sum(counts.values())} "
    f"canonical={counts['TASK_SCAN_CANONICAL ']} "
    f"legacy={counts['TASK_SCAN_LEGACY ']} "
    f"corrupt={counts['TASK_SCAN_CORRUPT ']} "
    f"invalid={counts['TASK_SCAN_INVALID ']}"
)
archive_lines.append(summary)
archive_out.write_text("\n".join(archive_lines) + "\n", encoding="utf-8")
PY
else
  : > "$ARCHIVE_OUT"
fi

python3 - "$ACTIVE_OUT" "$ARCHIVE_OUT" "$COMBINED_OUT" "$REPORT_OUT" <<'PY'
import datetime as dt
import pathlib
import sys

active_path = pathlib.Path(sys.argv[1])
archive_path = pathlib.Path(sys.argv[2])
combined_path = pathlib.Path(sys.argv[3])
report_path = pathlib.Path(sys.argv[4])

prefixes = {
    "canonical": "TASK_SCAN_CANONICAL ",
    "legacy": "TASK_SCAN_LEGACY ",
    "corrupt": "TASK_SCAN_CORRUPT ",
    "invalid": "TASK_SCAN_INVALID ",
}


def parse_scan(path: pathlib.Path):
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    counts = {k: 0 for k in prefixes}
    items = {k: [] for k in prefixes}
    summary_line = ""

    for line in lines:
        matched = False
        for kind, prefix in prefixes.items():
            if line.startswith(prefix):
                counts[kind] += 1
                items[kind].append(line)
                matched = True
                break
        if not matched and line.startswith("SCAN_SUMMARY "):
            summary_line = line

    return lines, counts, items, summary_line


active_lines, active_counts, active_items, active_summary = parse_scan(active_path)
archive_lines, archive_counts, archive_items, archive_summary = parse_scan(archive_path)
combined_lines, combined_counts, combined_items, combined_summary = parse_scan(combined_path)

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def section_lines(title, counts, items, summary_line):
    out = []
    out.append(f"## {title}")
    out.append("")
    out.append(f"- canonical: {counts['canonical']}")
    out.append(f"- legacy: {counts['legacy']}")
    out.append(f"- corrupt: {counts['corrupt']}")
    out.append(f"- invalid: {counts['invalid']}")
    out.append("")
    if summary_line:
        out.append(f"`{summary_line}`")
        out.append("")
    for kind in ("legacy", "corrupt", "invalid"):
        out.append(f"### {kind.capitalize()}")
        out.append("")
        if items[kind]:
            for line in items[kind]:
                out.append(f"- `{line}`")
        else:
            out.append("- none")
        out.append("")
    return out


report = []
report.append("# Task Legacy Baseline Audit: Golem")
report.append("")
report.append("## Timestamp")
report.append("")
report.append(f"- generated_at_utc: `{now}`")
report.append("")
report.append("## Scope")
report.append("")
report.append("- `tasks/` active inventory")
report.append("- `tasks/archive/` archived inventory")
report.append("- raw outputs saved under `diagnostics/task_audit/`")
report.append("")
report.extend(section_lines("Active Tasks", active_counts, active_items, active_summary))
report.extend(section_lines("Archive Tasks", archive_counts, archive_items, archive_summary))
report.append("## Combined Totals")
report.append("")
report.append(f"- canonical: {combined_counts['canonical']}")
report.append(f"- legacy: {combined_counts['legacy']}")
report.append(f"- corrupt: {combined_counts['corrupt']}")
report.append(f"- invalid: {combined_counts['invalid']}")
report.append("")
if combined_summary:
    report.append(f"`{combined_summary}`")
    report.append("")
report.append("## Reading")
report.append("")
report.append("- `canonical` ya está en carril nuevo.")
report.append("- `legacy` puede migrarse con el carril conservador actual.")
report.append("- `corrupt` requiere atención prioritaria porque ni siquiera parsea.")
report.append("- `invalid` requiere revisión puntual porque parsea pero no encaja bien.")
report.append("")
report.append("## Next Step")
report.append("")
report.append("La próxima acción correcta es seleccionar la primera tanda real de tratamiento:")
report.append("")
report.append("1. revisar los `corrupt`;")
report.append("2. decidir si se reparan o se aíslan;")
report.append("3. luego migrar legacy simples en tandas chicas.")
report.append("")

report_path.write_text("\n".join(report) + "\n", encoding="utf-8")
print(report_path)
PY

printf '\n== active ==\n'
cat "$ACTIVE_OUT"
printf '\n== archive ==\n'
cat "$ARCHIVE_OUT"
printf '\n== report ==\n'
cat "$REPORT_OUT"
