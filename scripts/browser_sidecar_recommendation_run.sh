#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_recommendation_run.sh [--format json|markdown] [--save-slug slug] <recommend-task.json>

Ejemplos:
  ./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-openclaw-public-baseline.json
  ./scripts/browser_sidecar_recommendation_run.sh --format json browser_tasks/recommend-reserved-domains-reference-pack.json
  ./scripts/browser_sidecar_recommendation_run.sh --save-slug recommend-run browser_tasks/recommend-openclaw-public-baseline.json
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

NORMALIZED_TASK="$TMP_ROOT/recommendation_task.normalized.json"
python3 - <<'PY' "$task_manifest" "$NORMALIZED_TASK"
import json
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2])
data = json.loads(manifest_path.read_text(encoding="utf-8"))

required = [
    "task_id",
    "title",
    "description",
    "question",
    "sources",
    "decision_criteria",
    "alternatives",
]
for key in required:
    if key not in data:
        raise SystemExit(f"ERROR: falta campo requerido en recommendation manifest: {key}")

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
    weight = int(criterion.get("weight", criterion.get("priority", 1)))
    if weight <= 0:
        raise SystemExit(f"ERROR: weight invalido para criterion {criterion_id}")
    evidence_terms = [
        str(item).strip()
        for item in criterion.get("evidence_terms", criterion.get("evidence_hints", []))
        if str(item).strip()
    ]
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

alternatives = data["alternatives"]
if not isinstance(alternatives, list) or len(alternatives) < 2:
    raise SystemExit("ERROR: alternatives debe ser una lista con al menos dos alternativas")

normalized_alternatives = []
alternative_ids = set()
cost_levels = {"low", "medium", "high"}
for idx, alternative in enumerate(alternatives):
    if not isinstance(alternative, dict):
        raise SystemExit(f"ERROR: alternative {idx} no es un objeto")
    alternative_id = str(alternative.get("alternative_id", "")).strip()
    label = str(alternative.get("label", "")).strip()
    description = str(alternative.get("description", "")).strip()
    intended_outcome = str(alternative.get("intended_outcome", "")).strip()
    primary_source = str(alternative.get("primary_source", "")).strip()
    relative_cost = str(alternative.get("relative_cost", "")).strip().lower()
    relative_cost_note = str(alternative.get("relative_cost_note", "")).strip()
    suggested_next_step = str(alternative.get("suggested_next_step", "")).strip()
    notes = str(alternative.get("notes", "")).strip()

    if not alternative_id or not label or not description or not intended_outcome:
        raise SystemExit(f"ERROR: alternative {idx} requiere alternative_id/label/description/intended_outcome")
    if not slug_re.match(alternative_id):
        raise SystemExit(f"ERROR: alternative_id invalido: {alternative_id}")
    if alternative_id in alternative_ids:
        raise SystemExit(f"ERROR: alternative_id duplicado: {alternative_id}")
    alternative_ids.add(alternative_id)

    source_plan = [str(item).strip() for item in alternative.get("source_plan", []) if str(item).strip()]
    if not source_plan:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere source_plan")
    for source_label in source_plan:
        if source_label not in labels:
            raise SystemExit(f"ERROR: alternative {alternative_id} referencia source inexistente: {source_label}")
    if primary_source and primary_source not in source_plan:
        raise SystemExit(f"ERROR: alternative {alternative_id} tiene primary_source fuera de source_plan")
    if not primary_source:
        primary_source = source_plan[0]

    if relative_cost not in cost_levels:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere relative_cost low|medium|high")
    if not relative_cost_note:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere relative_cost_note")

    risk_hints = [str(item).strip() for item in alternative.get("risk_hints", []) if str(item).strip()]
    preconditions = [str(item).strip() for item in alternative.get("preconditions", []) if str(item).strip()]
    if not risk_hints:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere risk_hints")
    if not preconditions:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere preconditions")
    if not suggested_next_step:
        raise SystemExit(f"ERROR: alternative {alternative_id} requiere suggested_next_step")

    normalized_alternatives.append(
        {
            "alternative_id": alternative_id,
            "label": label,
            "description": description,
            "intended_outcome": intended_outcome,
            "source_plan": source_plan,
            "primary_source": primary_source,
            "relative_cost": relative_cost,
            "relative_cost_note": relative_cost_note,
            "risk_hints": risk_hints,
            "preconditions": preconditions,
            "suggested_next_step": suggested_next_step,
            "notes": notes,
        }
    )

normalized = {
    "task_kind": "recommendation",
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
    "alternatives": normalized_alternatives,
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

DECISION_STDOUT="$TMP_ROOT/decision.stdout.json"
DECISION_STDERR="$TMP_ROOT/decision.stderr.log"
"$SCRIPT_DIR/browser_sidecar_decision_run.sh" --format json --save-slug "$FINAL_SLUG" "$NORMALIZED_TASK" >"$DECISION_STDOUT" 2>"$DECISION_STDERR"

dossier_json_artifact="$(sed -n 's/^DECISION_FINAL_ARTIFACT_JSON //p' "$DECISION_STDERR" | tail -n 1)"
dossier_md_artifact="$(sed -n 's/^DECISION_FINAL_ARTIFACT_MD //p' "$DECISION_STDERR" | tail -n 1)"
if [ -z "$dossier_json_artifact" ] || [ -z "$dossier_md_artifact" ]; then
  printf 'ERROR: no se pudieron detectar los artefactos del decision lane\n' >&2
  exit 1
fi

RECOMMEND_JSON="$TMP_ROOT/recommendation.final.json"
RECOMMEND_MD="$TMP_ROOT/recommendation.final.md"

python3 - <<'PY' "$NORMALIZED_TASK" "$DECISION_STDOUT" "$dossier_json_artifact" "$dossier_md_artifact" "$RECOMMEND_JSON" "$RECOMMEND_MD"
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

task = json.load(open(sys.argv[1], encoding="utf-8"))
decision = json.load(open(sys.argv[2], encoding="utf-8"))
decision_json_artifact = sys.argv[3]
decision_md_artifact = sys.argv[4]
recommendation_json_path = Path(sys.argv[5])
recommendation_md_path = Path(sys.argv[6])

criteria = decision["decision_criteria"]
source_ranking = decision["source_ranking"]
source_map = {item["label"]: item for item in source_ranking}
source_meta = {
    item["label"]: {
        "title": item["title"],
        "url": item["url"],
    }
    for item in source_ranking
}
criterion_map = {item["criterion_id"]: item for item in criteria}
cost_priority = {"low": 3, "medium": 2, "high": 1}

alternatives = []
for alternative in task["alternatives"]:
    criterion_strengths = []
    total_evidence_score = 0
    weak_criteria = []
    unsupported_criteria = []

    for criterion in criteria:
        relevant_scores = [
            source_score
            for source_score in criterion["source_scores"]
            if source_score["label"] in alternative["source_plan"]
        ]
        relevant_scores.sort(
            key=lambda item: (
                item["weighted_score"],
                item["score"],
                item["matched_terms_count"],
                item["total_line_hits"],
            ),
            reverse=True,
        )
        best = relevant_scores[0]
        total_evidence_score += best["weighted_score"]
        if best["score"] == 0:
            unsupported_criteria.append(criterion["criterion_id"])
        elif best["score"] <= 2:
            weak_criteria.append(criterion["criterion_id"])

        criterion_strengths.append(
            {
                "criterion_id": criterion["criterion_id"],
                "label": criterion["label"],
                "weight": criterion["weight"],
                "selected_source": {
                    "label": best["label"],
                    "title": best["title"],
                    "url": best["url"],
                },
                "score": best["score"],
                "weighted_score": best["weighted_score"],
                "matched_terms_count": best["matched_terms_count"],
                "total_line_hits": best["total_line_hits"],
                "short_assessment": best["short_assessment"],
                "uncertainty_note": best["uncertainty_note"],
                "extract_json": best["artifacts"]["extract_json"],
            }
        )

    supported_by_sources = []
    for label in alternative["source_plan"]:
        meta = source_meta[label]
        supported_by_sources.append(
            {
                "label": label,
                "title": meta["title"],
                "url": meta["url"],
                "source_total_weighted_score": source_map[label]["total_weighted_score"],
            }
        )

    if unsupported_criteria:
        alternative_uncertainty = (
            f'La alternativa deja {len(unsupported_criteria)} criterio(s) sin sosten claro: '
            + ", ".join(unsupported_criteria[:3])
            + "."
        )
    elif weak_criteria:
        alternative_uncertainty = (
            f'La alternativa deja {len(weak_criteria)} criterio(s) todavia debiles: '
            + ", ".join(weak_criteria[:3])
            + "."
        )
    elif len(alternative["source_plan"]) == 1:
        alternative_uncertainty = "La alternativa depende de una sola fuente principal."
    else:
        alternative_uncertainty = "La alternativa tiene cobertura usable dentro de los limites de lectura publica visible."

    alternatives.append(
        {
            "alternative_id": alternative["alternative_id"],
            "label": alternative["label"],
            "description": alternative["description"],
            "intended_outcome": alternative["intended_outcome"],
            "source_plan": alternative["source_plan"],
            "primary_source": alternative["primary_source"],
            "relative_cost": alternative["relative_cost"],
            "relative_cost_note": alternative["relative_cost_note"],
            "risk_hints": alternative["risk_hints"],
            "preconditions": alternative["preconditions"],
            "suggested_next_step": alternative["suggested_next_step"],
            "notes": alternative["notes"],
            "supported_by_sources": supported_by_sources,
            "criterion_strengths": criterion_strengths,
            "total_evidence_score": total_evidence_score,
            "criteria_won": [],
            "unsupported_criteria": unsupported_criteria,
            "weak_criteria": weak_criteria,
            "uncertainty_note": alternative_uncertainty,
        }
    )

for criterion in criteria:
    best_weighted = max(
        item["weighted_score"]
        for alternative in alternatives
        for item in alternative["criterion_strengths"]
        if item["criterion_id"] == criterion["criterion_id"]
    )
    if best_weighted <= 0:
        continue
    for alternative in alternatives:
        for item in alternative["criterion_strengths"]:
            if item["criterion_id"] == criterion["criterion_id"] and item["weighted_score"] == best_weighted:
                alternative["criteria_won"].append(criterion["criterion_id"])

alternatives.sort(
    key=lambda item: (
        item["total_evidence_score"],
        len(item["criteria_won"]),
        cost_priority[item["relative_cost"]],
        -len(item["preconditions"]),
        -len(item["risk_hints"]),
    ),
    reverse=True,
)

for idx, alternative in enumerate(alternatives, start=1):
    alternative["recommendation_rank"] = idx

winner = alternatives[0]
runner_up = alternatives[1] if len(alternatives) > 1 else None
margin = winner["total_evidence_score"] - runner_up["total_evidence_score"] if runner_up else winner["total_evidence_score"]

if margin >= 12:
    confidence = "strong"
elif margin >= 5:
    confidence = "moderate"
else:
    confidence = "weak"

discarded = []
for alternative in alternatives[1:]:
    reasons = []
    delta = winner["total_evidence_score"] - alternative["total_evidence_score"]
    if delta > 0:
        reasons.append(
            f'Tiene {delta} punto(s) menos de evidencia agregada que la alternativa recomendada.'
        )
    if cost_priority[alternative["relative_cost"]] < cost_priority[winner["relative_cost"]]:
        reasons.append(
            f'Requiere un costo relativo mas alto ({alternative["relative_cost"]}) que la recomendada ({winner["relative_cost"]}).'
        )
    if len(alternative["unsupported_criteria"]) > len(winner["unsupported_criteria"]):
        reasons.append(
            f'Deja mas criterios sin sostener: {", ".join(alternative["unsupported_criteria"][:3])}.'
        )
    elif len(alternative["weak_criteria"]) > len(winner["weak_criteria"]) and alternative["weak_criteria"]:
        reasons.append(
            f'Mantiene criterios mas debiles: {", ".join(alternative["weak_criteria"][:3])}.'
        )
    if len(alternative["preconditions"]) > len(winner["preconditions"]):
        reasons.append("Carga mas precondiciones operativas que la alternativa recomendada.")
    if not reasons:
        reasons.append("Quedo por debajo en el ranking final sin una ventaja clara sobre la recomendada.")
    discarded.append(
        {
            "alternative_id": alternative["alternative_id"],
            "label": alternative["label"],
            "reasons": reasons,
        }
    )

uncertainties = []
if margin < 5:
    uncertainties.append("El margen frente al runner-up es acotado; la recomendacion no deberia tratarse como un mandato absoluto.")
if winner["unsupported_criteria"]:
    uncertainties.append(
        "La alternativa recomendada todavia deja criterios sin sostener: "
        + ", ".join(winner["unsupported_criteria"][:3])
        + "."
    )
elif winner["weak_criteria"]:
    uncertainties.append(
        "La alternativa recomendada todavia deja criterios debiles: "
        + ", ".join(winner["weak_criteria"][:3])
        + "."
    )
uncertainties.append("La recomendacion se limita a evidencia publica visible; no incorpora login, host-private state ni interaccion compleja.")

verdict_rationale = [
    f'La alternativa recomendada es {winner["alternative_id"]} porque obtuvo el mayor total_evidence_score ({winner["total_evidence_score"]}).',
    f'Gano {len(winner["criteria_won"])} criterio(s): {", ".join(winner["criteria_won"]) if winner["criteria_won"] else "ninguno"}.',
    f'Su costo relativo declarado es {winner["relative_cost"]}.',
]
if runner_up:
    verdict_rationale.append(
        f'El runner-up fue {runner_up["alternative_id"]} con {runner_up["total_evidence_score"]}; el margen observado fue {margin}.'
    )
if discarded:
    verdict_rationale.append(
        f'Se descartaron {len(discarded)} alternativa(s) por menor evidencia agregada, mayor costo relativo o mas precondiciones.'
    )

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-recommendation",
    "task": {
        "task_id": task["task_id"],
        "title": task["title"],
        "description": task["description"],
        "question": task["question"],
        "output_slug": task["output_slug"],
        "manifest_path": task["manifest_path"],
    },
    "decision_artifacts": {
        "decision_json": decision_json_artifact,
        "decision_markdown": decision_md_artifact,
        "dossier_json": decision["dossier_artifacts"]["dossier_json"],
        "dossier_markdown": decision["dossier_artifacts"]["dossier_markdown"],
    },
    "recommendation_matrix": alternatives,
    "final_recommendation": {
        "recommended_alternative": {
            "alternative_id": winner["alternative_id"],
            "label": winner["label"],
            "description": winner["description"],
            "intended_outcome": winner["intended_outcome"],
        },
        "runner_up": {
            "alternative_id": runner_up["alternative_id"],
            "label": runner_up["label"],
        } if runner_up else None,
        "confidence": confidence,
        "margin_vs_runner_up": margin,
        "rationale": verdict_rationale,
        "discarded_alternatives": discarded,
        "risks": winner["risk_hints"],
        "preconditions": winner["preconditions"],
        "relative_cost": winner["relative_cost"],
        "relative_cost_note": winner["relative_cost_note"],
        "uncertainties": uncertainties,
        "suggested_next_step": winner["suggested_next_step"],
    },
}

recommendation_json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

lines = []
lines.append(f'# Browser Sidecar Recommendation: {task["title"]}')
lines.append("")
lines.append(f'generated_at: {payload["generated_at"]}')
lines.append(f'artifact_kind: {payload["artifact_kind"]}')
lines.append(f'task_id: {task["task_id"]}')
lines.append(f'manifest_path: {task["manifest_path"]}')
lines.append("")
lines.append("## Question")
lines.append(task["question"])
lines.append("")
lines.append("## Base Artifacts")
lines.append(f'- dossier_json: {payload["decision_artifacts"]["dossier_json"]}')
lines.append(f'- dossier_markdown: {payload["decision_artifacts"]["dossier_markdown"]}')
lines.append(f'- decision_json: {payload["decision_artifacts"]["decision_json"]}')
lines.append(f'- decision_markdown: {payload["decision_artifacts"]["decision_markdown"]}')
lines.append("")
lines.append("## Recommendation Ranking")
for alternative in alternatives:
    lines.append(
        f'- {alternative["alternative_id"]}: evidence_score={alternative["total_evidence_score"]}, criteria_won={len(alternative["criteria_won"])}, cost={alternative["relative_cost"]}'
    )
lines.append("")
lines.append("## Recommendation Matrix")
for alternative in alternatives:
    lines.append(f'### {alternative["alternative_id"]}')
    lines.append(f'- label: {alternative["label"]}')
    lines.append(f'- recommendation_rank: {alternative["recommendation_rank"]}')
    lines.append(f'- intended_outcome: {alternative["intended_outcome"]}')
    lines.append(f'- source_plan: {", ".join(alternative["source_plan"])}')
    lines.append(f'- primary_source: {alternative["primary_source"]}')
    lines.append(f'- total_evidence_score: {alternative["total_evidence_score"]}')
    lines.append(f'- criteria_won: {", ".join(alternative["criteria_won"]) if alternative["criteria_won"] else "(ninguno)"}')
    lines.append(f'- relative_cost: {alternative["relative_cost"]}')
    lines.append(f'- relative_cost_note: {alternative["relative_cost_note"]}')
    lines.append(f'- uncertainty_note: {alternative["uncertainty_note"]}')
    lines.append("- supported_by_sources:")
    for source in alternative["supported_by_sources"]:
      lines.append(
          f'  - {source["label"]}: {source["title"]} :: {source["url"]} (source_total_weighted_score={source["source_total_weighted_score"]})'
      )
    lines.append("- criterion_strengths:")
    for item in alternative["criterion_strengths"]:
      lines.append(
          f'  - {item["criterion_id"]}: source={item["selected_source"]["label"]}, score={item["score"]}/5, weighted_score={item["weighted_score"]}'
      )
      lines.append(f'    - assessment: {item["short_assessment"]}')
      lines.append(f'    - extract_json: {item["extract_json"]}')
    lines.append("- risks:")
    for item in alternative["risk_hints"]:
      lines.append(f'  - {item}')
    lines.append("- preconditions:")
    for item in alternative["preconditions"]:
      lines.append(f'  - {item}')
    lines.append(f'- suggested_next_step: {alternative["suggested_next_step"]}')
    lines.append("")

lines.append("## Final Recommendation")
lines.append(f'- recommended_alternative: {payload["final_recommendation"]["recommended_alternative"]["alternative_id"]}')
if payload["final_recommendation"]["runner_up"]:
    lines.append(f'- runner_up: {payload["final_recommendation"]["runner_up"]["alternative_id"]}')
lines.append(f'- confidence: {payload["final_recommendation"]["confidence"]}')
lines.append(f'- margin_vs_runner_up: {payload["final_recommendation"]["margin_vs_runner_up"]}')
lines.append(f'- relative_cost: {payload["final_recommendation"]["relative_cost"]}')
lines.append(f'- relative_cost_note: {payload["final_recommendation"]["relative_cost_note"]}')
lines.append("- rationale:")
for item in payload["final_recommendation"]["rationale"]:
    lines.append(f'  - {item}')
lines.append("- risks:")
for item in payload["final_recommendation"]["risks"]:
    lines.append(f'  - {item}')
lines.append("- preconditions:")
for item in payload["final_recommendation"]["preconditions"]:
    lines.append(f'  - {item}')
lines.append("- discarded_alternatives:")
for item in payload["final_recommendation"]["discarded_alternatives"]:
    lines.append(f'  - {item["alternative_id"]}:')
    for reason in item["reasons"]:
        lines.append(f'    - {reason}')
lines.append("- uncertainties:")
for item in payload["final_recommendation"]["uncertainties"]:
    lines.append(f'  - {item}')
lines.append(f'- suggested_next_step: {payload["final_recommendation"]["suggested_next_step"]}')
lines.append("")

recommendation_md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

browser_sidecar_make_outbox
final_json_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_recommendation" json)"
final_md_path="$(browser_sidecar_artifact_path "${FINAL_SLUG}_recommendation" md)"
cp "$RECOMMEND_JSON" "$final_json_path"
cp "$RECOMMEND_MD" "$final_md_path"
"$VALIDATE_MARKDOWN" "$final_md_path" >/dev/null

printf 'RECOMMENDATION_FINAL_ARTIFACT_JSON %s\n' "$(browser_sidecar_display_repo_path "$final_json_path")" >&2
printf 'RECOMMENDATION_FINAL_ARTIFACT_MD %s\n' "$(browser_sidecar_display_repo_path "$final_md_path")" >&2

if [ "$format" = "json" ]; then
  cat "$RECOMMEND_JSON"
else
  cat "$RECOMMEND_MD"
fi
