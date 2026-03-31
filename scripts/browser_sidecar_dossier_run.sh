#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_dossier_run.sh [--format json|markdown] [--save-slug slug] <task-manifest.json>

Ejemplos:
  ./scripts/browser_sidecar_dossier_run.sh browser_tasks/reserved-domains-technical.json
  ./scripts/browser_sidecar_dossier_run.sh --format json browser_tasks/iana-service-overview.json
  ./scripts/browser_sidecar_dossier_run.sh --save-slug reserved-dossier browser_tasks/reserved-domains-technical.json
USAGE
}

format="markdown"
save_slug_override=""
task_manifest=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --format)
      format="${2:-}"
      shift 2
      ;;
    --json)
      format="json"
      shift
      ;;
    --markdown)
      format="markdown"
      shift
      ;;
    --save-slug)
      save_slug_override="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'ERROR: opcion no reconocida: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$task_manifest" ]; then
        printf 'ERROR: manifest extra no esperado: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      task_manifest="$1"
      shift
      ;;
  esac
done

if [ -z "$task_manifest" ] || [ "$#" -gt 0 ]; then
  usage >&2
  exit 2
fi

case "$format" in
  json|markdown) ;;
  *)
    printf 'ERROR: formato invalido: %s\n' "$format" >&2
    exit 2
    ;;
esac

if [ ! -f "$task_manifest" ]; then
  printf 'ERROR: no existe el manifest: %s\n' "$task_manifest" >&2
  exit 2
fi

if [ -n "$save_slug_override" ]; then
  browser_sidecar_validate_slug "$save_slug_override"
fi

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

NORMALIZED_TASK="$TMP_ROOT/task.normalized.json"
python3 - <<'PY' "$task_manifest" "$NORMALIZED_TASK"
import json
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2])
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["task_id", "title", "description", "sources"]
for key in required:
    if key not in data:
        raise SystemExit(f"ERROR: falta campo requerido en manifest: {key}")

task_id = str(data["task_id"]).strip()
title = str(data["title"]).strip()
description = str(data["description"]).strip()
if not task_id or not title or not description:
    raise SystemExit("ERROR: task_id/title/description no pueden estar vacios")

slug_re = re.compile(r"^[A-Za-z0-9._-]+$")
if not slug_re.match(task_id):
    raise SystemExit("ERROR: task_id invalido; usa solo letras, numeros, punto, guion y guion bajo")

output_slug = str(data.get("output_slug", task_id)).strip()
if not slug_re.match(output_slug):
    raise SystemExit("ERROR: output_slug invalido")

sources = data["sources"]
if not isinstance(sources, list) or len(sources) < 2:
    raise SystemExit("ERROR: sources debe ser una lista con al menos dos fuentes")

normalized_sources = []
labels = set()
for idx, source in enumerate(sources):
    if not isinstance(source, dict):
        raise SystemExit(f"ERROR: source {idx} no es un objeto")
    label = str(source.get("label", "")).strip()
    url = str(source.get("url", "")).strip()
    selector_hint = str(source.get("selector_hint", "")).strip()
    notes = str(source.get("notes", "")).strip()
    if not label or not url:
        raise SystemExit(f"ERROR: source {idx} requiere label y url")
    if not slug_re.match(label):
        raise SystemExit(f"ERROR: label invalido para source {idx}: {label}")
    if label in labels:
        raise SystemExit(f"ERROR: label duplicado en sources: {label}")
    labels.add(label)
    normalized_sources.append(
        {
            "label": label,
            "url": url,
            "selector_hint": selector_hint,
            "notes": notes,
        }
    )

focus_terms = [str(item).strip() for item in data.get("focus_terms", []) if str(item).strip()]
expected_signals = [str(item).strip() for item in data.get("expected_signals", []) if str(item).strip()]
focus_profile = data.get("focus_profile", {}) or {}
excerpt_limit = int(focus_profile.get("excerpt_limit", 8))
match_limit = int(focus_profile.get("match_limit", 3))
if excerpt_limit <= 0 or match_limit <= 0:
    raise SystemExit("ERROR: focus_profile.excerpt_limit y match_limit deben ser enteros positivos")

comparisons = data.get("comparisons", []) or []
normalized_comparisons = []
if comparisons:
    for idx, comparison in enumerate(comparisons):
        if not isinstance(comparison, dict):
            raise SystemExit(f"ERROR: comparison {idx} no es un objeto")
        label = str(comparison.get("label", "")).strip()
        left = str(comparison.get("left", "")).strip()
        right = str(comparison.get("right", "")).strip()
        if not label or not left or not right:
            raise SystemExit(f"ERROR: comparison {idx} requiere label/left/right")
        if not slug_re.match(label):
            raise SystemExit(f"ERROR: comparison label invalido: {label}")
        if left not in labels or right not in labels:
            raise SystemExit(f"ERROR: comparison {label} referencia labels inexistentes")
        if left == right:
            raise SystemExit(f"ERROR: comparison {label} no puede comparar la misma fuente")
        normalized_comparisons.append({"label": label, "left": left, "right": right})
else:
    normalized_comparisons.append(
        {
            "label": f"{normalized_sources[0]['label']}-vs-{normalized_sources[1]['label']}",
            "left": normalized_sources[0]["label"],
            "right": normalized_sources[1]["label"],
        }
    )

comparison_mode = str(data.get("comparison_mode", "explicit_pairs")).strip() or "explicit_pairs"

normalized = {
    "task_id": task_id,
    "title": title,
    "description": description,
    "output_slug": output_slug,
    "comparison_mode": comparison_mode,
    "focus_terms": focus_terms,
    "expected_signals": expected_signals,
    "focus_profile": {
        "excerpt_limit": excerpt_limit,
        "match_limit": match_limit,
    },
    "sources": normalized_sources,
    "comparisons": normalized_comparisons,
    "manifest_path": str(manifest_path),
}

out_path.write_text(json.dumps(normalized, ensure_ascii=False, indent=2), encoding="utf-8")
PY

TASK_OUTPUT_SLUG="$(python3 - <<'PY' "$NORMALIZED_TASK"
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["output_slug"])
PY
)"
FINAL_SLUG="${save_slug_override:-$TASK_OUTPUT_SLUG}"
browser_sidecar_validate_slug "$FINAL_SLUG"

if ! browser_sidecar_running || ! browser_sidecar_listener_ready; then
  "$SCRIPT_DIR/browser_sidecar_start.sh" >/dev/null
fi
browser_sidecar_require_running

mkdir -p "$TMP_ROOT/source-records" "$TMP_ROOT/compare-records" "$TMP_ROOT/stdout" "$TMP_ROOT/stderr"

while IFS=$'\t' read -r source_label source_url; do
  "$SCRIPT_DIR/browser_sidecar_open.sh" "$source_url" >/dev/null
  sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"
done < <(
  python3 - <<'PY' "$NORMALIZED_TASK"
import json
import sys

task = json.load(open(sys.argv[1], encoding="utf-8"))
for source in task["sources"]:
    print(f'{source["label"]}\t{source["url"]}')
PY
)

tabs_snapshot_json="$(browser_sidecar_tabs_json)"

while IFS=$'\t' read -r source_label source_url; do
  selection_json="$(browser_sidecar_resolve_latest_url_json "$source_url")"
  selection_index="$(python3 - <<'PY' "$selection_json"
import json
import sys
print(json.loads(sys.argv[1])["index"])
PY
)"

  extract_stdout="$TMP_ROOT/stdout/${source_label}.extract.json"
  extract_stderr="$TMP_ROOT/stderr/${source_label}.extract.stderr"
  extract_slug="${FINAL_SLUG}_extract_${source_label}"
  "$SCRIPT_DIR/browser_sidecar_extract.sh" --format json --save-slug "$extract_slug" "$selection_index" >"$extract_stdout" 2>"$extract_stderr"

  extract_json_artifact="$(sed -n 's/^EXTRACT_ARTIFACT_JSON //p' "$extract_stderr" | tail -n 1)"
  extract_md_artifact="$(sed -n 's/^EXTRACT_ARTIFACT_MD //p' "$extract_stderr" | tail -n 1)"
  if [ -z "$extract_json_artifact" ] || [ -z "$extract_md_artifact" ]; then
    printf 'ERROR: no se pudieron detectar los artefactos de extract para %s\n' "$source_label" >&2
    exit 1
  fi

  python3 - <<'PY' \
    "$NORMALIZED_TASK" \
    "$source_label" \
    "$selection_json" \
    "$tabs_snapshot_json" \
    "$extract_stdout" \
    "$extract_json_artifact" \
    "$extract_md_artifact" \
    >"$TMP_ROOT/source-records/${source_label}.json"
import json
import sys

task = json.load(open(sys.argv[1], encoding="utf-8"))
source_label = sys.argv[2]
selection = json.loads(sys.argv[3])
tabs_snapshot = json.loads(sys.argv[4])
extract_payload = json.load(open(sys.argv[5], encoding="utf-8"))
extract_json_artifact = sys.argv[6]
extract_md_artifact = sys.argv[7]

source = next(item for item in task["sources"] if item["label"] == source_label)
focus_terms = task["focus_terms"]
expected_signals = task["expected_signals"]
match_limit = task["focus_profile"]["match_limit"]
excerpt_limit = task["focus_profile"]["excerpt_limit"]

text_lines = extract_payload["content"]["text_lines"]
links = extract_payload["content"]["links"]

focus_matches = []
for term in focus_terms:
    matches = []
    lower_term = term.lower()
    for line_number, line in enumerate(text_lines, start=1):
        if lower_term in line.lower():
            matches.append({"line_number": line_number, "text": line})
    if matches:
        focus_matches.append(
            {
                "term": term,
                "match_count": len(matches),
                "sample_matches": matches[:match_limit],
            }
        )

signal_hits = []
for signal in expected_signals:
    lower_signal = signal.lower()
    text_found = any(lower_signal in line.lower() for line in text_lines)
    link_found = any(
        lower_signal in (link.get("text", "") or "").lower()
        or lower_signal in (link.get("url", "") or "").lower()
        for link in links
    )
    title_found = lower_signal in selection.get("title", "").lower()
    if text_found or link_found or title_found:
        signal_hits.append(signal)

record = {
    "label": source["label"],
    "source": source,
    "resolved_selection": {
        "match_type": selection.get("match_type", ""),
        "index": selection.get("index"),
        "title": selection.get("title", ""),
        "url": selection.get("url", ""),
        "id": selection.get("id", ""),
    },
    "tabs_snapshot": tabs_snapshot,
    "extract_summary": {
        "line_count": extract_payload["content"]["line_count"],
        "unique_line_count": extract_payload["content"]["unique_line_count"],
        "word_count": extract_payload["content"]["word_count"],
        "link_count": extract_payload["content"]["link_count"],
        "excerpt_lines": extract_payload["content"]["excerpt_lines"][:excerpt_limit],
    },
    "focus": {
        "matched_terms_count": len(focus_matches),
        "matched_terms": focus_matches,
        "expected_signal_hits": signal_hits,
    },
    "artifacts": {
        "extract_json": extract_json_artifact,
        "extract_markdown": extract_md_artifact,
    },
    "extract_payload": extract_payload,
}

print(json.dumps(record, ensure_ascii=False, indent=2))
PY
done < <(
  python3 - <<'PY' "$NORMALIZED_TASK"
import json
import sys

task = json.load(open(sys.argv[1], encoding="utf-8"))
for source in task["sources"]:
    print(f'{source["label"]}\t{source["url"]}')
PY
)

while IFS=$'\t' read -r comparison_label comparison_left comparison_right; do
  left_index="$(python3 - <<'PY' "$TMP_ROOT/source-records/${comparison_left}.json"
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["resolved_selection"]["index"])
PY
)"
  right_index="$(python3 - <<'PY' "$TMP_ROOT/source-records/${comparison_right}.json"
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["resolved_selection"]["index"])
PY
)"

  compare_stdout="$TMP_ROOT/stdout/${comparison_label}.compare.json"
  compare_stderr="$TMP_ROOT/stderr/${comparison_label}.compare.stderr"
  compare_slug="${FINAL_SLUG}_compare_${comparison_label}"
  "$SCRIPT_DIR/browser_sidecar_compare.sh" --format json --save-slug "$compare_slug" "$left_index" "$right_index" >"$compare_stdout" 2>"$compare_stderr"

  compare_json_artifact="$(sed -n 's/^COMPARE_ARTIFACT_JSON //p' "$compare_stderr" | tail -n 1)"
  compare_md_artifact="$(sed -n 's/^COMPARE_ARTIFACT_MD //p' "$compare_stderr" | tail -n 1)"
  if [ -z "$compare_json_artifact" ] || [ -z "$compare_md_artifact" ]; then
    printf 'ERROR: no se pudieron detectar los artefactos de compare para %s\n' "$comparison_label" >&2
    exit 1
  fi

  python3 - <<'PY' \
    "$NORMALIZED_TASK" \
    "$comparison_label" \
    "$compare_stdout" \
    "$compare_json_artifact" \
    "$compare_md_artifact" \
    >"$TMP_ROOT/compare-records/${comparison_label}.json"
import json
import sys

task = json.load(open(sys.argv[1], encoding="utf-8"))
comparison_label = sys.argv[2]
compare_payload = json.load(open(sys.argv[3], encoding="utf-8"))
compare_json_artifact = sys.argv[4]
compare_md_artifact = sys.argv[5]

comparison = next(item for item in task["comparisons"] if item["label"] == comparison_label)

record = {
    "label": comparison_label,
    "comparison": comparison,
    "artifacts": {
        "compare_json": compare_json_artifact,
        "compare_markdown": compare_md_artifact,
    },
    "compare_payload": compare_payload,
}

print(json.dumps(record, ensure_ascii=False, indent=2))
PY
done < <(
  python3 - <<'PY' "$NORMALIZED_TASK"
import json
import sys

task = json.load(open(sys.argv[1], encoding="utf-8"))
for comparison in task["comparisons"]:
    print(f'{comparison["label"]}\t{comparison["left"]}\t{comparison["right"]}')
PY
)

DOSSIER_JSON="$TMP_ROOT/dossier.final.json"
DOSSIER_MD="$TMP_ROOT/dossier.final.md"

python3 - <<'PY' "$NORMALIZED_TASK" "$TMP_ROOT/source-records" "$TMP_ROOT/compare-records" "$DOSSIER_JSON" "$DOSSIER_MD"
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

task = json.load(open(sys.argv[1], encoding="utf-8"))
source_dir = Path(sys.argv[2])
compare_dir = Path(sys.argv[3])
json_out = Path(sys.argv[4])
md_out = Path(sys.argv[5])

source_records = []
for source in task["sources"]:
    record_path = source_dir / f'{source["label"]}.json'
    source_records.append(json.load(open(record_path, encoding="utf-8")))

compare_records = []
for comparison in task["comparisons"]:
    record_path = compare_dir / f'{comparison["label"]}.json'
    compare_records.append(json.load(open(record_path, encoding="utf-8")))

source_focus_totals = [
    {
        "label": record["label"],
        "title": record["resolved_selection"]["title"],
        "matched_terms_count": record["focus"]["matched_terms_count"],
        "expected_signal_hits_count": len(record["focus"]["expected_signal_hits"]),
    }
    for record in source_records
]
source_focus_totals.sort(
    key=lambda item: (item["matched_terms_count"], item["expected_signal_hits_count"]),
    reverse=True,
)

conclusion = []
conclusion.append(
    f'Se procesaron {len(source_records)} fuentes publicas para la tarea {task["task_id"]}.'
)
if source_focus_totals:
    top = source_focus_totals[0]
    conclusion.append(
        f'La fuente con mas coincidencias de foco fue {top["label"]} ({top["matched_terms_count"]} terminos, {top["expected_signal_hits_count"]} senales esperadas).'
    )
conclusion.append(
    f'Se generaron {len(compare_records)} comparaciones segun comparison_mode={task["comparison_mode"]}.'
)
conclusion.append(
    "El dossier lane sigue limitado a lectura publica, sin login, clicks complejos ni automatizacion general."
)

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-dossier",
    "task": {
        "task_id": task["task_id"],
        "title": task["title"],
        "description": task["description"],
        "output_slug": task["output_slug"],
        "comparison_mode": task["comparison_mode"],
        "manifest_path": task["manifest_path"],
    },
    "focus": {
        "terms": task["focus_terms"],
        "expected_signals": task["expected_signals"],
        "focus_profile": task["focus_profile"],
    },
    "sources": source_records,
    "comparisons": compare_records,
    "conclusion": conclusion,
}

json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

lines = []
lines.append(f'# Browser Sidecar Dossier: {task["title"]}')
lines.append("")
lines.append(f'generated_at: {payload["generated_at"]}')
lines.append(f'artifact_kind: {payload["artifact_kind"]}')
lines.append(f'task_id: {task["task_id"]}')
lines.append(f'comparison_mode: {task["comparison_mode"]}')
lines.append(f'manifest_path: {task["manifest_path"]}')
lines.append("")
lines.append("## Description")
lines.append(task["description"])
lines.append("")
lines.append("## Focus")
if task["focus_terms"]:
    for term in task["focus_terms"]:
        lines.append(f'- term: {term}')
else:
    lines.append("- term: (sin focus_terms)")
if task["expected_signals"]:
    for signal in task["expected_signals"]:
        lines.append(f'- expected_signal: {signal}')
else:
    lines.append("- expected_signal: (sin expected_signals)")
lines.append("")
lines.append("## Sources")
for record in source_records:
    selection = record["resolved_selection"]
    summary = record["extract_summary"]
    focus = record["focus"]
    lines.append(f'### {record["label"]}')
    lines.append(f'- title: {selection["title"]}')
    lines.append(f'- url: {selection["url"]}')
    lines.append(f'- match_type: {selection["match_type"]}')
    lines.append(f'- selection_index: {selection["index"]}')
    lines.append(f'- line_count: {summary["line_count"]}')
    lines.append(f'- word_count: {summary["word_count"]}')
    lines.append(f'- link_count: {summary["link_count"]}')
    lines.append(f'- extract_json: {record["artifacts"]["extract_json"]}')
    lines.append(f'- extract_markdown: {record["artifacts"]["extract_markdown"]}')
    lines.append("- excerpt:")
    for line in summary["excerpt_lines"]:
        lines.append(f'  - {line}')
    if not summary["excerpt_lines"]:
        lines.append("  - (sin excerpt)")
    lines.append("- focus_matches:")
    for match in focus["matched_terms"]:
        lines.append(f'  - term: {match["term"]} ({match["match_count"]})')
        for sample in match["sample_matches"]:
            lines.append(f'    - line {sample["line_number"]}: {sample["text"]}')
    if not focus["matched_terms"]:
        lines.append("  - (sin matches)")
    lines.append("- expected_signal_hits:")
    for signal in focus["expected_signal_hits"]:
        lines.append(f'  - {signal}')
    if not focus["expected_signal_hits"]:
        lines.append("  - (sin hits)")
    lines.append("")

lines.append("## Comparisons")
for record in compare_records:
    comparison = record["comparison"]
    payload_cmp = record["compare_payload"]
    summary = payload_cmp["comparison"]
    lines.append(f'### {record["label"]}')
    lines.append(f'- left: {comparison["left"]}')
    lines.append(f'- right: {comparison["right"]}')
    lines.append(f'- similarity_ratio: {summary["similarity_ratio"]}')
    lines.append(f'- common_line_count: {summary["common_line_count"]}')
    lines.append(f'- only_in_a_count: {summary["only_in_a_count"]}')
    lines.append(f'- only_in_b_count: {summary["only_in_b_count"]}')
    lines.append(f'- compare_json: {record["artifacts"]["compare_json"]}')
    lines.append(f'- compare_markdown: {record["artifacts"]["compare_markdown"]}')
    lines.append("- conclusion:")
    for line in payload_cmp["conclusion"]:
        lines.append(f'  - {line}')
    lines.append("")

lines.append("## Conclusion")
for line in conclusion:
    lines.append(f'- {line}')
lines.append("")

md_out.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

browser_sidecar_make_outbox
final_json_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_dossier" json)"
final_md_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_dossier" md)"
cp "$DOSSIER_JSON" "$final_json_path"
cp "$DOSSIER_MD" "$final_md_path"
"$VALIDATE_MARKDOWN" "$final_md_path" >/dev/null

printf 'DOSSIER_FINAL_ARTIFACT_JSON %s\n' "$(browser_sidecar_display_repo_path "$final_json_path")" >&2
printf 'DOSSIER_FINAL_ARTIFACT_MD %s\n' "$(browser_sidecar_display_repo_path "$final_md_path")" >&2

if [ "$format" = "json" ]; then
  cat "$DOSSIER_JSON"
else
  cat "$DOSSIER_MD"
fi
