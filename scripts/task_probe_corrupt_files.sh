#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SCAN_FILE="diagnostics/task_audit/active_scan.txt"
OUT_DIR="diagnostics/task_audit/corrupt_probe"
PATHS_OUT="diagnostics/task_audit/corrupt_paths.txt"

mkdir -p "$OUT_DIR"

[[ -f "$SCAN_FILE" ]] || {
  echo "Missing scan file: $SCAN_FILE" >&2
  exit 2
}

python3 - "$SCAN_FILE" "$PATHS_OUT" "$OUT_DIR" <<'PY'
import json
import pathlib
import sys

scan_file = pathlib.Path(sys.argv[1])
paths_out = pathlib.Path(sys.argv[2])
out_dir = pathlib.Path(sys.argv[3])

lines = scan_file.read_text(encoding="utf-8").splitlines()
corrupt_paths = []

for line in lines:
    if line.startswith("TASK_SCAN_CORRUPT "):
        prefix, rest = line.split(" ", 1)
        marker = " tasks/"
        idx = rest.find(marker)
        if idx == -1:
            marker = " /"
            idx = rest.find(marker)
        if idx == -1:
            continue
        path = rest[idx + 1 :].strip()
        corrupt_paths.append(path)

paths_out.write_text("\n".join(corrupt_paths) + ("\n" if corrupt_paths else ""), encoding="utf-8")

for raw_path in corrupt_paths:
    path = pathlib.Path(raw_path)
    safe_name = path.name + ".probe.txt"
    probe_path = out_dir / safe_name

    report = []
    report.append(f"PATH: {path}")
    report.append(f"EXISTS: {path.exists()}")

    if not path.exists():
        report.append("STATUS: missing")
        probe_path.write_text("\n".join(report) + "\n", encoding="utf-8")
        continue

    size = path.stat().st_size
    report.append(f"SIZE_BYTES: {size}")

    raw = path.read_text(encoding="utf-8", errors="replace")

    try:
        json.loads(raw)
        report.append("JSON_PARSE: OK (unexpected for corrupt baseline)")
    except Exception as e:
        report.append(f"JSON_PARSE: FAIL")
        report.append(f"ERROR_TYPE: {type(e).__name__}")
        report.append(f"ERROR_MSG: {e}")

    sample = raw[:1200]
    report.append("")
    report.append("RAW_SAMPLE_BEGIN")
    report.append(sample)
    report.append("RAW_SAMPLE_END")
    report.append("")

    stripped = raw.strip()
    if not stripped:
        diagnosis = "empty-or-whitespace"
    elif stripped[0] not in "[{":
        diagnosis = "non-json-leading-content"
    elif raw.count("{") != raw.count("}") or raw.count("[") != raw.count("]"):
        diagnosis = "likely-truncated-or-unbalanced"
    else:
        diagnosis = "structured-but-json-invalid"
    report.append(f"INITIAL_DIAGNOSIS: {diagnosis}")

    probe_path.write_text("\n".join(report) + "\n", encoding="utf-8")

print(f"CORRUPT_PATH_COUNT {len(corrupt_paths)}")
for p in corrupt_paths:
    print(p)
PY

printf '\n== corrupt paths ==\n'
cat "$PATHS_OUT"

printf '\n== probe files ==\n'
find "$OUT_DIR" -maxdepth 1 -type f -name '*.probe.txt' | sort
