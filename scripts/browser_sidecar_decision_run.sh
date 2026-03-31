#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_decision_run.sh [--format json|markdown] [--save-slug slug] <decision-task.json>

Ejemplos:
  ./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-reserved-domains-best-source.json
  ./scripts/browser_sidecar_decision_run.sh --format json browser_tasks/decision-iana-first-source.json
  ./scripts/browser_sidecar_decision_run.sh --save-slug decision-run browser_tasks/decision-reserved-domains-best-source.json
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

NORMALIZED_TASK="$TMP_ROOT/decision_task.normalized.json"
python3 - <<'PY' "$task_manifest" "$NORMALIZED_TASK"
import json
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2])
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = ["task_id", "title", "description", "question", "sources", "decision_criteria"]
for key in required:
    if key not in data:
        raise SystemExit(f"ERROR: falta campo requerido en decision manifest: {key}")

slug_re = re.compile(r"^[A-Za-z0-9._-]+$")

def require_text(name):
    value = str(data.get(name, "")).strip()
    if not value:
        raise SystemExit(f"ERROR: {name} no puede estar vacio")
    return value

task_id = require_text("task_id")
title = require_text("title")
description = require_text("description")
question = require_text("question")

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

decision_criteria = data["decision_criteria"]
if not isinstance(decision_criteria, list) or not decision_criteria:
    raise SystemExit("ERROR: decision_criteria debe tener al menos un criterio")

normalized_criteria = []
criterion_ids = set()
for idx, criterion in enumerate(decision_criteria):
    if not isinstance(criterion, dict):
        raise SystemExit(f"ERROR: criterion {idx} no es un objeto")
    criterion_id = str(criterion.get("criterion_id", "")).strip()
    label = str(criterion.get("label", "")).strip()
    description = str(criterion.get("description", "")).strip()
    notes = str(criterion.get("notes", "")).strip()
    if not criterion_id or not label or not description:
        raise SystemExit(f"ERROR: criterion {idx} requiere criterion_id/label/description")
    if not slug_re.match(criterion_id):
        raise SystemExit(f"ERROR: criterion_id invalido: {criterion_id}")
    if criterion_id in criterion_ids:
        raise SystemExit(f"ERROR: criterion_id duplicado: {criterion_id}")
    criterion_ids.add(criterion_id)

    weight_raw = criterion.get("weight", criterion.get("priority", 1))
    weight = int(weight_raw)
    if weight <= 0:
        raise SystemExit(f"ERROR: weight invalido para criterion {criterion_id}")

    evidence_terms = [str(item).strip() for item in criterion.get("evidence_terms", criterion.get("evidence_hints", [])) if str(item).strip()]
    if not evidence_terms:
        raise SystemExit(f"ERROR: criterion {criterion_id} requiere evidence_terms o evidence_hints")

    scoring_rule = str(criterion.get("scoring_rule", "coverage_v1")).strip() or "coverage_v1"

    normalized_criteria.append(
        {
            "criterion_id": criterion_id,
            "label": label,
            "description": description,
            "weight": weight,
            "evidence_terms": evidence_terms,
            "scoring_rule": scoring_rule,
            "notes": notes,
        }
    )

normalized = {
    "task_kind": "decision",
    "task_id": task_id,
    "title": title,
    "description": description,
    "question": question,
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
    "decision_criteria": normalized_criteria,
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

DOSSIER_STDOUT="$TMP_ROOT/dossier.stdout.json"
DOSSIER_STDERR="$TMP_ROOT/dossier.stderr.log"
"$SCRIPT_DIR/browser_sidecar_dossier_run.sh" --format json --save-slug "$FINAL_SLUG" "$task_manifest" >"$DOSSIER_STDOUT" 2>"$DOSSIER_STDERR"

dossier_json_artifact="$(sed -n 's/^DOSSIER_FINAL_ARTIFACT_JSON //p' "$DOSSIER_STDERR" | tail -n 1)"
dossier_md_artifact="$(sed -n 's/^DOSSIER_FINAL_ARTIFACT_MD //p' "$DOSSIER_STDERR" | tail -n 1)"
if [ -z "$dossier_json_artifact" ] || [ -z "$dossier_md_artifact" ]; then
  printf 'ERROR: no se pudieron detectar los artefactos del dossier base\n' >&2
  exit 1
fi

DECISION_JSON="$TMP_ROOT/decision.final.json"
DECISION_MD="$TMP_ROOT/decision.final.md"

python3 - <<'PY' "$NORMALIZED_TASK" "$DOSSIER_STDOUT" "$dossier_json_artifact" "$dossier_md_artifact" "$DECISION_JSON" "$DECISION_MD"
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

task = json.load(open(sys.argv[1], encoding="utf-8"))
dossier = json.load(open(sys.argv[2], encoding="utf-8"))
dossier_json_artifact = sys.argv[3]
dossier_md_artifact = sys.argv[4]
decision_json_path = Path(sys.argv[5])
decision_md_path = Path(sys.argv[6])

criteria = task["decision_criteria"]
source_records = dossier["sources"]
comparison_records = dossier["comparisons"]

def collect_term_evidence(source_record, term):
    lower_term = term.lower()
    selection = source_record["resolved_selection"]
    extract_payload = source_record["extract_payload"]
    lines = extract_payload["content"]["text_lines"]
    links = extract_payload["content"]["links"]

    title_hit = lower_term in selection["title"].lower()
    url_hit = lower_term in selection["url"].lower()

    line_hits = []
    for idx, line in enumerate(lines, start=1):
        if lower_term in line.lower():
            line_hits.append({"line_number": idx, "text": line})

    link_hits = []
    for link in links:
        link_text = (link.get("text") or "")
        link_url = (link.get("url") or "")
        if lower_term in link_text.lower() or lower_term in link_url.lower():
            link_hits.append({"text": link_text, "url": link_url})

    return {
        "term": term,
        "title_hit": title_hit,
        "url_hit": url_hit,
        "line_hits": line_hits[:3],
        "line_hit_count": len(line_hits),
        "link_hits": link_hits[:2],
        "link_hit_count": len(link_hits),
    }

criterion_results = []
source_totals = {
    record["label"]: {
        "label": record["label"],
        "title": record["resolved_selection"]["title"],
        "url": record["resolved_selection"]["url"],
        "total_weighted_score": 0,
        "criteria_won": [],
        "criteria_scores": [],
    }
    for record in source_records
}

for criterion in criteria:
    source_scores = []
    for record in source_records:
        evidence_records = []
        total_line_hits = 0
        matched_term_count = 0
        title_or_url_support = False
        link_support = False
        for term in criterion["evidence_terms"]:
            evidence = collect_term_evidence(record, term)
            if evidence["title_hit"] or evidence["url_hit"] or evidence["line_hit_count"] or evidence["link_hit_count"]:
                evidence_records.append(evidence)
                matched_term_count += 1
                total_line_hits += evidence["line_hit_count"]
                if evidence["title_hit"] or evidence["url_hit"]:
                    title_or_url_support = True
                if evidence["link_hit_count"]:
                    link_support = True

        if matched_term_count == 0:
            score = 0
        elif matched_term_count == 1:
            score = 2
        elif matched_term_count == 2:
            score = 3
        else:
            score = 4

        if matched_term_count >= 4 and total_line_hits >= 6:
            score = 5
        elif title_or_url_support and score >= 4:
            score = 5
        elif title_or_url_support and score == 3:
            score = 4

        weighted_score = score * criterion["weight"]
        if score == 0:
            assessment = "Sin evidencia util para este criterio."
            uncertainty = "El criterio queda sin sosten claro en las fuentes leidas."
        elif score <= 2:
            assessment = "Cobertura debil o parcial para este criterio."
            uncertainty = "La evidencia existe pero sigue siendo limitada o poco diversa."
        elif score == 3:
            assessment = "Cobertura moderada con evidencia textual explicita."
            uncertainty = "La cobertura es usable, pero no necesariamente dominante."
        elif score == 4:
            assessment = "Cobertura fuerte con apoyo visible en texto y/o metadatos."
            uncertainty = "La evidencia es fuerte, aunque no cubre todos los terminos esperados."
        else:
            assessment = "Cobertura muy fuerte con varias senales explicitas."
            uncertainty = "La principal incertidumbre es de alcance, no de ausencia de evidencia."

        source_score = {
            "label": record["label"],
            "title": record["resolved_selection"]["title"],
            "url": record["resolved_selection"]["url"],
            "score": score,
            "weighted_score": weighted_score,
            "matched_terms_count": matched_term_count,
            "total_line_hits": total_line_hits,
            "title_or_url_support": title_or_url_support,
            "link_support": link_support,
            "matched_evidence": evidence_records,
            "short_assessment": assessment,
            "uncertainty_note": uncertainty,
            "artifacts": record["artifacts"],
        }
        source_scores.append(source_score)
        source_totals[record["label"]]["total_weighted_score"] += weighted_score
        source_totals[record["label"]]["criteria_scores"].append(
            {
                "criterion_id": criterion["criterion_id"],
                "label": criterion["label"],
                "score": score,
                "weighted_score": weighted_score,
            }
        )

    source_scores.sort(
        key=lambda item: (
            item["weighted_score"],
            item["score"],
            item["matched_terms_count"],
            item["total_line_hits"],
        ),
        reverse=True,
    )
    best_weighted = source_scores[0]["weighted_score"]
    best_sources = [item["label"] for item in source_scores if item["weighted_score"] == best_weighted and item["weighted_score"] > 0]
    for label in best_sources:
        source_totals[label]["criteria_won"].append(criterion["criterion_id"])

    if best_weighted == 0:
        criterion_uncertainty = "Ninguna fuente sostuvo este criterio con evidencia suficiente."
    elif len(best_sources) > 1:
        criterion_uncertainty = "Hay empate en el mejor sosten del criterio; la conclusion aqui es debil."
    elif source_scores[0]["score"] <= 2:
        criterion_uncertainty = "El criterio tiene un ganador, pero con evidencia todavia limitada."
    else:
        criterion_uncertainty = "El criterio tiene un sosten principal razonablemente claro."

    related_comparisons = [
        {
            "label": record["label"],
            "compare_json": record["artifacts"]["compare_json"],
            "compare_markdown": record["artifacts"]["compare_markdown"],
        }
        for record in comparison_records
        if record["comparison"]["left"] in {item["label"] for item in source_scores[:2]}
        or record["comparison"]["right"] in {item["label"] for item in source_scores[:2]}
    ]

    criterion_results.append(
        {
            "criterion_id": criterion["criterion_id"],
            "label": criterion["label"],
            "description": criterion["description"],
            "weight": criterion["weight"],
            "evidence_terms": criterion["evidence_terms"],
            "scoring_rule": criterion["scoring_rule"],
            "notes": criterion["notes"],
            "best_sources": best_sources,
            "short_assessment": source_scores[0]["short_assessment"],
            "uncertainty_note": criterion_uncertainty,
            "source_scores": source_scores,
            "related_comparisons": related_comparisons,
        }
    )

source_ranking = list(source_totals.values())
source_ranking.sort(
    key=lambda item: (
        item["total_weighted_score"],
        len(item["criteria_won"]),
    ),
    reverse=True,
)

winner = source_ranking[0]
runner_up = source_ranking[1] if len(source_ranking) > 1 else None
margin = winner["total_weighted_score"] - runner_up["total_weighted_score"] if runner_up else winner["total_weighted_score"]

if margin >= 8:
    confidence = "strong"
elif margin >= 4:
    confidence = "moderate"
else:
    confidence = "weak"

winner_source_record = next(record for record in source_records if record["label"] == winner["label"])
winner_criteria = [item for item in criterion_results if winner["label"] in item["best_sources"]]
challenger_criteria = []
if runner_up:
    challenger_criteria = [item for item in criterion_results if runner_up["label"] in item["best_sources"]]

uncertainties = []
for item in criterion_results:
    if "empate" in item["uncertainty_note"].lower() or "limitad" in item["uncertainty_note"].lower() or "ninguna" in item["uncertainty_note"].lower():
        uncertainties.append(item["uncertainty_note"])
if not uncertainties:
    uncertainties.append("La decision sigue limitada a lectura publica visible; no incluye navegacion privada ni interaccion compleja.")

verdict_rationale = [
    f'La fuente recomendada es {winner["label"]} porque obtuvo el mayor total_weighted_score ({winner["total_weighted_score"]}).',
    f'Gano {len(winner["criteria_won"])} criterio(s): {", ".join(winner["criteria_won"]) if winner["criteria_won"] else "ninguno"}.' ,
]
if runner_up:
    verdict_rationale.append(
        f'La segunda fuente fue {runner_up["label"]} con {runner_up["total_weighted_score"]}; el margen observado fue {margin}.'
    )
if challenger_criteria:
    verdict_rationale.append(
        f'La mejor alternativa todavia retiene criterios propios: {", ".join(item["criterion_id"] for item in challenger_criteria)}.'
    )

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-decision",
    "task": {
        "task_id": task["task_id"],
        "title": task["title"],
        "description": task["description"],
        "question": task["question"],
        "output_slug": task["output_slug"],
        "manifest_path": task["manifest_path"],
    },
    "dossier_artifacts": {
        "dossier_json": dossier_json_artifact,
        "dossier_markdown": dossier_md_artifact,
    },
    "decision_criteria": criterion_results,
    "source_ranking": source_ranking,
    "final_verdict": {
        "recommended_source": {
            "label": winner["label"],
            "title": winner_source_record["resolved_selection"]["title"],
            "url": winner_source_record["resolved_selection"]["url"],
        },
        "confidence": confidence,
        "margin_vs_runner_up": margin,
        "rationale": verdict_rationale,
        "uncertainties": uncertainties,
    },
}

decision_json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

lines = []
lines.append(f'# Browser Sidecar Decision: {task["title"]}')
lines.append("")
lines.append(f'generated_at: {payload["generated_at"]}')
lines.append(f'artifact_kind: {payload["artifact_kind"]}')
lines.append(f'task_id: {task["task_id"]}')
lines.append(f'manifest_path: {task["manifest_path"]}')
lines.append("")
lines.append("## Question")
lines.append(task["question"])
lines.append("")
lines.append("## Dossier Base")
lines.append(f'- dossier_json: {dossier_json_artifact}')
lines.append(f'- dossier_markdown: {dossier_md_artifact}')
lines.append("")
lines.append("## Source Ranking")
for item in source_ranking:
    lines.append(f'- {item["label"]}: total_weighted_score={item["total_weighted_score"]}, criteria_won={len(item["criteria_won"])}')
lines.append("")
lines.append("## Criterion Matrix")
for criterion in criterion_results:
    lines.append(f'### {criterion["criterion_id"]}')
    lines.append(f'- label: {criterion["label"]}')
    lines.append(f'- weight: {criterion["weight"]}')
    lines.append(f'- best_sources: {", ".join(criterion["best_sources"]) if criterion["best_sources"] else "(sin ganador)"}')
    lines.append(f'- short_assessment: {criterion["short_assessment"]}')
    lines.append(f'- uncertainty_note: {criterion["uncertainty_note"]}')
    lines.append("- evidence_terms:")
    for term in criterion["evidence_terms"]:
        lines.append(f'  - {term}')
    lines.append("- source_scores:")
    for source_score in criterion["source_scores"]:
        lines.append(
            f'  - {source_score["label"]}: score={source_score["score"]}/5, weighted_score={source_score["weighted_score"]}, matched_terms={source_score["matched_terms_count"]}, line_hits={source_score["total_line_hits"]}'
        )
        lines.append(f'    - assessment: {source_score["short_assessment"]}')
        lines.append(f'    - uncertainty: {source_score["uncertainty_note"]}')
        lines.append(f'    - extract_json: {source_score["artifacts"]["extract_json"]}')
        for evidence in source_score["matched_evidence"][:2]:
            sample_bits = []
            if evidence["title_hit"]:
                sample_bits.append("title_hit=yes")
            if evidence["url_hit"]:
                sample_bits.append("url_hit=yes")
            if evidence["line_hits"]:
                first_line = evidence["line_hits"][0]
                sample_bits.append(f'line {first_line["line_number"]}: {first_line["text"]}')
            elif evidence["link_hits"]:
                first_link = evidence["link_hits"][0]
                sample_bits.append(f'link: {first_link["text"]} :: {first_link["url"]}')
            lines.append(f'    - evidence {evidence["term"]}: {" | ".join(sample_bits)}')
    if criterion["related_comparisons"]:
        lines.append("- related_comparisons:")
        for related in criterion["related_comparisons"]:
            lines.append(f'  - {related["label"]}: {related["compare_markdown"]}')
    lines.append("")

lines.append("## Final Verdict")
lines.append(f'- recommended_source: {payload["final_verdict"]["recommended_source"]["label"]}')
lines.append(f'- recommended_title: {payload["final_verdict"]["recommended_source"]["title"]}')
lines.append(f'- recommended_url: {payload["final_verdict"]["recommended_source"]["url"]}')
lines.append(f'- confidence: {payload["final_verdict"]["confidence"]}')
lines.append(f'- margin_vs_runner_up: {payload["final_verdict"]["margin_vs_runner_up"]}')
lines.append("- rationale:")
for line in payload["final_verdict"]["rationale"]:
    lines.append(f'  - {line}')
lines.append("- uncertainties:")
for line in payload["final_verdict"]["uncertainties"]:
    lines.append(f'  - {line}')
lines.append("")

decision_md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

browser_sidecar_make_outbox
final_json_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_decision" json)"
final_md_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_decision" md)"
cp "$DECISION_JSON" "$final_json_path"
cp "$DECISION_MD" "$final_md_path"
"$VALIDATE_MARKDOWN" "$final_md_path" >/dev/null

printf 'DECISION_FINAL_ARTIFACT_JSON %s\n' "$(browser_sidecar_display_repo_path "$final_json_path")" >&2
printf 'DECISION_FINAL_ARTIFACT_MD %s\n' "$(browser_sidecar_display_repo_path "$final_md_path")" >&2

if [ "$format" = "json" ]; then
  cat "$DECISION_JSON"
else
  cat "$DECISION_MD"
fi
