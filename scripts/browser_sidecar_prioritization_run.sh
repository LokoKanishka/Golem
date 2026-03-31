#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_prioritization_run.sh [--format json|markdown] [--save-slug slug] <prioritize-task.json>

Ejemplos:
  ./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-golem-openclaw-next-tranche.json
  ./scripts/browser_sidecar_prioritization_run.sh --format json browser_tasks/prioritize-project-evidence-maintenance.json
  ./scripts/browser_sidecar_prioritization_run.sh --save-slug prioritize-run browser_tasks/prioritize-golem-openclaw-next-tranche.json
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

browser_sidecar_require_running
browser_sidecar_make_outbox

python3 - <<'PY' \
  "$task_manifest" \
  "$format" \
  "$save_slug_override" \
  "$GOLEM_BROWSER_SIDECAR_REPO_ROOT" \
  "$GOLEM_BROWSER_SIDECAR_OUTBOX_DIR" \
  "$SCRIPT_DIR" \
  "$VALIDATE_MARKDOWN"
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


manifest_arg, output_format, save_slug_override, repo_root_arg, outbox_arg, script_dir_arg, validate_markdown = sys.argv[1:8]
repo_root = Path(repo_root_arg).resolve()
outbox_dir = Path(outbox_arg).resolve()
script_dir = Path(script_dir_arg).resolve()
manifest_path = Path(manifest_arg).resolve()

slug_re = re.compile(r"^[A-Za-z0-9._-]+$")
COST_PENALTY = {"low": 0, "medium": 3, "high": 6}
ACTIVE_BUCKETS = ("NOW", "NEXT", "LATER")


def normalize_text_line(line: str) -> str:
    line = line.replace("\t", " ").strip()
    line = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", line)
    line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
    line = re.sub(r"^\s*#+\s*", "", line)
    line = re.sub(r"^\s*[-*+]\s*", "", line)
    line = re.sub(r"^\s*\d+\.\s*", "", line)
    line = line.replace("`", "")
    line = re.sub(r"\s+", " ", line)
    return line.strip()


def load_manifest() -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = [
        "task_id",
        "title",
        "description",
        "question",
        "sources",
        "local_sources",
        "decision_criteria",
        "project_fronts",
        "priority_buckets",
    ]
    for key in required:
        if key not in data:
            raise SystemExit(f"ERROR: falta campo requerido en prioritization manifest: {key}")

    def req_text(name: str) -> str:
        value = str(data.get(name, "")).strip()
        if not value:
            raise SystemExit(f"ERROR: {name} no puede estar vacio")
        return value

    task_id = req_text("task_id")
    if not slug_re.match(task_id):
        raise SystemExit("ERROR: task_id invalido")
    output_slug = str(data.get("output_slug", task_id)).strip()
    if not slug_re.match(output_slug):
        raise SystemExit("ERROR: output_slug invalido")

    focus_terms = [str(item).strip() for item in data.get("focus_terms", []) if str(item).strip()]
    expected_signals = [str(item).strip() for item in data.get("expected_signals", []) if str(item).strip()]
    focus_profile = data.get("focus_profile", {}) or {}
    excerpt_limit = int(focus_profile.get("excerpt_limit", 10))
    match_limit = int(focus_profile.get("match_limit", 3))
    if excerpt_limit <= 0 or match_limit <= 0:
        raise SystemExit("ERROR: focus_profile.excerpt_limit y match_limit deben ser enteros positivos")

    public_sources = []
    local_sources = []
    source_labels = set()

    for idx, source in enumerate(data["sources"]):
        if not isinstance(source, dict):
            raise SystemExit(f"ERROR: source {idx} no es un objeto")
        label = str(source.get("label", "")).strip()
        url = str(source.get("url", "")).strip()
        selector_hint = str(source.get("selector_hint", "")).strip()
        notes = str(source.get("notes", "")).strip()
        if not label or not url:
            raise SystemExit(f"ERROR: source {idx} requiere label y url")
        if not slug_re.match(label):
            raise SystemExit(f"ERROR: label invalido en source {idx}: {label}")
        if label in source_labels:
            raise SystemExit(f"ERROR: label duplicado: {label}")
        source_labels.add(label)
        public_sources.append(
            {
                "label": label,
                "url": url,
                "selector_hint": selector_hint,
                "notes": notes,
                "kind": "public",
            }
        )

    for idx, source in enumerate(data["local_sources"]):
        if not isinstance(source, dict):
            raise SystemExit(f"ERROR: local_source {idx} no es un objeto")
        label = str(source.get("label", "")).strip()
        rel_path = str(source.get("path", "")).strip()
        notes = str(source.get("notes", "")).strip()
        if not label or not rel_path:
            raise SystemExit(f"ERROR: local_source {idx} requiere label y path")
        if not slug_re.match(label):
            raise SystemExit(f"ERROR: label invalido en local_source {idx}: {label}")
        if label in source_labels:
            raise SystemExit(f"ERROR: label duplicado: {label}")
        source_labels.add(label)
        abs_path = (repo_root / rel_path).resolve()
        if not abs_path.exists():
            raise SystemExit(f"ERROR: no existe local_source path: {rel_path}")
        local_sources.append(
            {
                "label": label,
                "path": rel_path,
                "abs_path": str(abs_path),
                "notes": notes,
                "kind": "local",
            }
        )

    criteria = []
    criterion_ids = set()
    for idx, criterion in enumerate(data["decision_criteria"]):
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
        weight = int(criterion.get("weight", 1))
        if weight <= 0:
            raise SystemExit(f"ERROR: weight invalido para criterion {criterion_id}")
        evidence_terms = [str(item).strip() for item in criterion.get("evidence_terms", []) if str(item).strip()]
        blocker_terms = [str(item).strip() for item in criterion.get("blocker_terms", []) if str(item).strip()]
        if not evidence_terms:
            raise SystemExit(f"ERROR: criterion {criterion_id} requiere evidence_terms")
        criteria.append(
            {
                "criterion_id": criterion_id,
                "label": label,
                "description": description,
                "weight": weight,
                "evidence_terms": evidence_terms,
                "blocker_terms": blocker_terms,
                "scoring_rule": str(criterion.get("scoring_rule", "coverage_v1")).strip() or "coverage_v1",
                "notes": notes,
            }
        )

    priority_buckets = []
    bucket_map = {}
    for idx, bucket in enumerate(data["priority_buckets"]):
        if not isinstance(bucket, dict):
            raise SystemExit(f"ERROR: priority_bucket {idx} no es un objeto")
        bucket_id = str(bucket.get("bucket_id", "")).strip()
        label = str(bucket.get("label", "")).strip()
        description = str(bucket.get("description", "")).strip()
        assignment_mode = str(bucket.get("assignment_mode", "")).strip()
        button = str(bucket.get("button", "")).strip().upper()
        if not bucket_id or not label or not description or not assignment_mode or not button:
            raise SystemExit(f"ERROR: priority_bucket {idx} requiere bucket_id/label/description/assignment_mode/button")
        bucket_obj = {
            "bucket_id": bucket_id,
            "label": label,
            "description": description,
            "assignment_mode": assignment_mode,
            "min_score": int(bucket.get("min_score", 0)),
            "max_blocker_hits": int(bucket.get("max_blocker_hits", 9999)),
            "button": button,
        }
        priority_buckets.append(bucket_obj)
        bucket_map[bucket_id] = bucket_obj
    expected_buckets = {"NOW", "NEXT", "LATER", "FROZEN", "DO_NOT_TOUCH", "REOPEN_ONLY_IF"}
    if set(bucket_map) != expected_buckets:
        raise SystemExit("ERROR: priority_buckets debe definir exactamente NOW/NEXT/LATER/FROZEN/DO_NOT_TOUCH/REOPEN_ONLY_IF")

    fronts = []
    front_ids = set()
    for idx, front in enumerate(data["project_fronts"]):
        if not isinstance(front, dict):
            raise SystemExit(f"ERROR: project_front {idx} no es un objeto")
        front_id = str(front.get("front_id", "")).strip()
        label = str(front.get("label", "")).strip()
        description = str(front.get("description", "")).strip()
        current_state_hint = str(front.get("current_state_hint", "")).strip()
        intended_outcome = str(front.get("intended_outcome", "")).strip()
        relative_cost = str(front.get("relative_cost", "")).strip().lower()
        relative_cost_note = str(front.get("relative_cost_note", "")).strip()
        recommended_action = str(front.get("recommended_action", "")).strip()
        notes = str(front.get("notes", "")).strip()
        if not front_id or not label or not description or not current_state_hint or not intended_outcome or not recommended_action:
            raise SystemExit(f"ERROR: project_front {idx} requiere front_id/label/description/current_state_hint/intended_outcome/recommended_action")
        if not slug_re.match(front_id):
            raise SystemExit(f"ERROR: front_id invalido: {front_id}")
        if front_id in front_ids:
            raise SystemExit(f"ERROR: front_id duplicado: {front_id}")
        front_ids.add(front_id)
        if relative_cost not in COST_PENALTY:
            raise SystemExit(f"ERROR: relative_cost invalido para front {front_id}")
        evidence_sources = [str(item).strip() for item in front.get("evidence_sources", []) if str(item).strip()]
        if not evidence_sources:
            raise SystemExit(f"ERROR: front {front_id} requiere evidence_sources")
        for label_ref in evidence_sources:
            if label_ref not in source_labels:
                raise SystemExit(f"ERROR: front {front_id} referencia source inexistente: {label_ref}")
        risk_hints = [str(item).strip() for item in front.get("risk_hints", []) if str(item).strip()]
        preconditions = [str(item).strip() for item in front.get("preconditions", []) if str(item).strip()]
        kill_criteria = [str(item).strip() for item in front.get("kill_criteria", []) if str(item).strip()]
        blocking_signals = [str(item).strip() for item in front.get("blocking_signals", []) if str(item).strip()]
        if not risk_hints or not preconditions or not kill_criteria:
            raise SystemExit(f"ERROR: front {front_id} requiere risk_hints, preconditions y kill_criteria")
        raw_bucket_signal_terms = front.get("bucket_signal_terms", {}) or {}
        bucket_signal_terms = {}
        for bucket_id, terms in raw_bucket_signal_terms.items():
            if bucket_id not in bucket_map:
                raise SystemExit(f"ERROR: front {front_id} usa bucket inexistente en bucket_signal_terms: {bucket_id}")
            normalized_terms = [str(item).strip() for item in terms if str(item).strip()]
            if normalized_terms:
                bucket_signal_terms[bucket_id] = normalized_terms
        fronts.append(
            {
                "front_id": front_id,
                "label": label,
                "description": description,
                "current_state_hint": current_state_hint,
                "evidence_sources": evidence_sources,
                "intended_outcome": intended_outcome,
                "relative_cost": relative_cost,
                "relative_cost_note": relative_cost_note,
                "risk_hints": risk_hints,
                "preconditions": preconditions,
                "kill_criteria": kill_criteria,
                "blocking_signals": blocking_signals,
                "bucket_signal_terms": bucket_signal_terms,
                "recommended_action": recommended_action,
                "notes": notes,
            }
        )

    return {
        "task_kind": "project_prioritization",
        "task_id": task_id,
        "title": req_text("title"),
        "description": req_text("description"),
        "question": req_text("question"),
        "output_slug": output_slug,
        "comparison_mode": str(data.get("comparison_mode", "explicit_pairs")).strip() or "explicit_pairs",
        "focus_terms": focus_terms,
        "expected_signals": expected_signals,
        "focus_profile": {
            "excerpt_limit": excerpt_limit,
            "match_limit": match_limit,
        },
        "sources": public_sources,
        "local_sources": local_sources,
        "decision_criteria": criteria,
        "priority_buckets": priority_buckets,
        "project_fronts": fronts,
        "manifest_path": str(manifest_path),
    }


def timestamped_path(slug: str, extension: str) -> Path:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return outbox_dir / f"{ts}_{slug}.{extension}"


def make_local_extract(source: dict, final_slug: str) -> dict:
    abs_path = Path(source["abs_path"])
    raw_text = abs_path.read_text(encoding="utf-8")
    text_lines = []
    links = []
    for raw_line in raw_text.splitlines():
        for text, url in re.findall(r"\[([^\]]+)\]\(([^)]+)\)", raw_line):
            links.append({"text": normalize_text_line(text), "url": url})
        normalized = normalize_text_line(raw_line)
        if normalized:
            text_lines.append(normalized)
    unique_lines = []
    seen = set()
    for line in text_lines:
        if line in seen:
            continue
        seen.add(line)
        unique_lines.append(line)
    word_count = sum(len(re.findall(r"\S+", line)) for line in text_lines)
    payload = {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "artifact_kind": "browser-sidecar-local-extract",
        "source_kind": "local_versioned",
        "target_input": source["path"],
        "selection": {
            "match_type": "local_path",
            "index": 0,
            "title": source["label"],
            "url": source["path"],
            "id": source["label"],
        },
        "snapshot": {
            "captured_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "selector": source["path"],
            "title": source["label"],
            "url": source["path"],
        },
        "content": {
            "line_count": len(text_lines),
            "unique_line_count": len(unique_lines),
            "word_count": word_count,
            "excerpt_lines": text_lines[:12],
            "text_lines": text_lines,
            "normalized_text": "\n".join(text_lines),
            "links": links,
            "link_count": len(links),
        },
    }
    markdown = []
    markdown.append(f"# Browser Sidecar Local Extract: {source['label']}")
    markdown.append("")
    markdown.append(f"generated_at: {payload['generated_at']}")
    markdown.append(f"artifact_kind: {payload['artifact_kind']}")
    markdown.append(f"source_kind: {payload['source_kind']}")
    markdown.append(f"source_path: {source['path']}")
    markdown.append(f"title: {source['label']}")
    markdown.append("")
    markdown.append("## Summary")
    markdown.append(f"- line_count: {payload['content']['line_count']}")
    markdown.append(f"- unique_line_count: {payload['content']['unique_line_count']}")
    markdown.append(f"- word_count: {payload['content']['word_count']}")
    markdown.append(f"- link_count: {payload['content']['link_count']}")
    markdown.append("")
    markdown.append("## Excerpt")
    excerpt = payload["content"]["excerpt_lines"] or ["(sin lineas visibles)"]
    markdown.extend(f"- {line}" for line in excerpt)
    markdown.append("")
    markdown.append("## Text")
    markdown.extend(f"- {line}" for line in payload["content"]["text_lines"])
    if not payload["content"]["text_lines"]:
        markdown.append("- (sin texto)")
    markdown.append("")
    markdown.append("## Links")
    if payload["content"]["links"]:
        for link in payload["content"]["links"]:
            markdown.append(f"- {link['text'] or '(sin texto)'} :: {link['url']}")
    else:
        markdown.append("- (sin links)")
    md_text = "\n".join(markdown) + "\n"

    json_slug = f"{final_slug}_local_{source['label']}"
    json_path = timestamped_path(json_slug, "json")
    md_path = timestamped_path(json_slug, "md")
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    md_path.write_text(md_text, encoding="utf-8")
    subprocess.run([validate_markdown, str(md_path)], check=True, stdout=subprocess.DEVNULL)
    source_record = {
        "label": source["label"],
        "kind": "local",
        "path": source["path"],
        "notes": source["notes"],
        "artifact_json": str(json_path.relative_to(repo_root)),
        "artifact_markdown": str(md_path.relative_to(repo_root)),
        "extract": payload,
    }
    return source_record


def make_public_fallback_extract(source: dict, base_payload: dict, final_slug: str, sidecar_json: str, sidecar_md: str) -> dict:
    html_response = subprocess.run(
        ["curl", "-fsSL", source["url"]],
        check=True,
        text=True,
        capture_output=True,
    )
    raw_html = html_response.stdout
    stripped = re.sub(r"(?is)<script.*?</script>", " ", raw_html)
    stripped = re.sub(r"(?is)<style.*?</style>", " ", stripped)
    stripped = re.sub(r"(?s)<[^>]+>", "\n", stripped)
    stripped = stripped.replace("&nbsp;", " ")
    text_lines = []
    for raw_line in stripped.splitlines():
        normalized = normalize_text_line(raw_line)
        if not normalized:
            continue
        if len(normalized) > 240:
            normalized = normalized[:240].rstrip()
        if not re.search(r"[A-Za-z]", normalized):
            continue
        if normalized not in text_lines:
            text_lines.append(normalized)
    title = base_payload["snapshot"].get("title") or source["selector_hint"] or source["label"]
    seed_lines = [title, source["notes"], source["selector_hint"], source["url"]]
    merged_lines = []
    seen = set()
    for line in seed_lines + text_lines:
        normalized = normalize_text_line(line or "")
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        merged_lines.append(normalized)
    merged_lines = merged_lines[:200]
    word_count = sum(len(re.findall(r"\S+", line)) for line in merged_lines)
    payload = {
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "artifact_kind": "browser-sidecar-public-fallback-extract",
        "source_kind": "public_sidecar_html_fallback",
        "target_input": source["url"],
        "selection": {
            "match_type": base_payload["selection"].get("match_type", ""),
            "index": base_payload["selection"].get("index", 0),
            "title": title,
            "url": source["url"],
            "id": base_payload["selection"].get("id", ""),
        },
        "snapshot": {
            "captured_at": base_payload["snapshot"].get("captured_at", ""),
            "selector": base_payload["snapshot"].get("selector", ""),
            "title": title,
            "url": source["url"],
        },
        "sidecar_artifacts": {
            "artifact_json": sidecar_json,
            "artifact_markdown": sidecar_md,
        },
        "content": {
            "line_count": len(merged_lines),
            "unique_line_count": len(merged_lines),
            "word_count": word_count,
            "excerpt_lines": merged_lines[:12],
            "text_lines": merged_lines,
            "normalized_text": "\n".join(merged_lines),
            "links": [],
            "link_count": 0,
        },
    }
    markdown = []
    markdown.append(f"# Browser Sidecar Public Fallback Extract: {title}")
    markdown.append("")
    markdown.append(f"generated_at: {payload['generated_at']}")
    markdown.append(f"artifact_kind: {payload['artifact_kind']}")
    markdown.append(f"source_kind: {payload['source_kind']}")
    markdown.append(f"url: {source['url']}")
    markdown.append(f"sidecar_artifact_json: {sidecar_json}")
    markdown.append(f"sidecar_artifact_markdown: {sidecar_md}")
    markdown.append("")
    markdown.append("## Summary")
    markdown.append(f"- line_count: {payload['content']['line_count']}")
    markdown.append(f"- word_count: {payload['content']['word_count']}")
    markdown.append("")
    markdown.append("## Excerpt")
    for line in payload["content"]["excerpt_lines"] or ["(sin lineas visibles)"]:
        markdown.append(f"- {line}")
    markdown.append("")
    markdown.append("## Text")
    for line in payload["content"]["text_lines"] or ["(sin texto)"]:
        markdown.append(f"- {line}")
    markdown_text = "\n".join(markdown) + "\n"

    json_slug = f"{final_slug}_public_{source['label']}_fallback"
    json_path = timestamped_path(json_slug, "json")
    md_path = timestamped_path(json_slug, "md")
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    md_path.write_text(markdown_text, encoding="utf-8")
    subprocess.run([validate_markdown, str(md_path)], check=True, stdout=subprocess.DEVNULL)
    return {
        "label": source["label"],
        "kind": "public",
        "url": source["url"],
        "selector_hint": source["selector_hint"],
        "notes": source["notes"],
        "artifact_json": str(json_path.relative_to(repo_root)),
        "artifact_markdown": str(md_path.relative_to(repo_root)),
        "extract": payload,
        "sidecar_artifact_json": sidecar_json,
        "sidecar_artifact_markdown": sidecar_md,
        "used_html_fallback": True,
    }


def run_public_extract(source: dict, final_slug: str) -> dict:
    slug = f"{final_slug}_public_{source['label']}"
    subprocess.run(
        [str(script_dir / "browser_sidecar_open.sh"), source["url"]],
        check=True,
        text=True,
        capture_output=True,
    )
    selector = source["selector_hint"].strip() or source["label"]
    resolve = subprocess.run(
        [
            "bash",
            "-lc",
            f"source '{script_dir / 'browser_sidecar_common.sh'}'; browser_sidecar_resolve_latest_url_json '{source['url']}'",
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    resolved = json.loads(resolve.stdout)
    selector = str(resolved.get("index", selector))
    cmd = [
        str(script_dir / "browser_sidecar_extract.sh"),
        "--format",
        "json",
        "--save-slug",
        slug,
        selector,
    ]
    completed = subprocess.run(cmd, check=True, text=True, capture_output=True)
    payload = json.loads(completed.stdout)
    json_match = re.findall(r"^EXTRACT_ARTIFACT_JSON (.+)$", completed.stderr, flags=re.MULTILINE)
    md_match = re.findall(r"^EXTRACT_ARTIFACT_MD (.+)$", completed.stderr, flags=re.MULTILINE)
    if not json_match or not md_match:
        raise SystemExit(f"ERROR: no se pudieron detectar artefactos para source {source['label']}")
    sidecar_json = json_match[-1].strip()
    sidecar_md = md_match[-1].strip()
    if payload["content"]["line_count"] == 0:
        return make_public_fallback_extract(source, payload, final_slug, sidecar_json, sidecar_md)
    source_record = {
        "label": source["label"],
        "kind": "public",
        "url": source["url"],
        "selector_hint": source["selector_hint"],
        "notes": source["notes"],
        "artifact_json": sidecar_json,
        "artifact_markdown": sidecar_md,
        "extract": payload,
    }
    return source_record


def collect_line_hits(source_record: dict, terms: list[str], limit: int) -> tuple[list[str], list[dict]]:
    matched_terms = []
    hits = []
    lines = source_record["extract"]["content"]["text_lines"]
    for term in terms:
        needle = term.lower()
        found = False
        for idx, line in enumerate(lines, start=1):
            if needle in line.lower():
                matched_terms.append(term)
                hits.append(
                    {
                        "source_label": source_record["label"],
                        "source_kind": source_record["kind"],
                        "line_number": idx,
                        "line": line,
                    }
                )
                found = True
                break
        if len(hits) >= limit:
            break
        if found:
            continue
    return matched_terms, hits


def score_from_matches(match_count: int) -> int:
    if match_count <= 0:
        return 0
    if match_count == 1:
        return 2
    if match_count == 2:
        return 3
    if match_count == 3:
        return 4
    return 5


manifest = load_manifest()
final_slug = save_slug_override.strip() or manifest["output_slug"]
if not slug_re.match(final_slug):
    raise SystemExit("ERROR: save_slug invalido")

public_records = [run_public_extract(source, final_slug) for source in manifest["sources"]]
local_records = [make_local_extract(source, final_slug) for source in manifest["local_sources"]]
source_map = {item["label"]: item for item in public_records + local_records}

focus_limit = manifest["focus_profile"]["match_limit"]
criteria = manifest["decision_criteria"]
bucket_map = {bucket["bucket_id"]: bucket for bucket in manifest["priority_buckets"]}
forced_bucket_order = [bucket["bucket_id"] for bucket in manifest["priority_buckets"] if bucket["assignment_mode"] == "forced"]

front_results = []
for front in manifest["project_fronts"]:
    evidence_records = [source_map[label] for label in front["evidence_sources"]]
    criterion_results = []
    public_lines = []
    local_lines = []
    overall_blockers = []
    for criterion in criteria:
        matched_terms = []
        blocker_terms = []
        evidence_hits = []
        blocker_hits = []
        supporting_sources = set()
        for source_record in evidence_records:
            terms, hits = collect_line_hits(source_record, criterion["evidence_terms"], focus_limit)
            for term in terms:
                if term not in matched_terms:
                    matched_terms.append(term)
            for hit in hits:
                if hit not in evidence_hits:
                    evidence_hits.append(hit)
                supporting_sources.add(source_record["label"])
                if hit["source_kind"] == "public" and hit["line"] not in public_lines:
                    public_lines.append(hit["line"])
                if hit["source_kind"] == "local" and hit["line"] not in local_lines:
                    local_lines.append(hit["line"])
            if criterion["blocker_terms"]:
                b_terms, b_hits = collect_line_hits(source_record, criterion["blocker_terms"], focus_limit)
                for term in b_terms:
                    if term not in blocker_terms:
                        blocker_terms.append(term)
                for hit in b_hits:
                    if hit not in blocker_hits:
                        blocker_hits.append(hit)
        raw_score = score_from_matches(len(matched_terms))
        adjusted_score = max(0, raw_score - min(2, len(blocker_terms)))
        weighted_score = adjusted_score * criterion["weight"]
        short_assessment = (
            "Cobertura muy fuerte con varias senales explicitas."
            if adjusted_score >= 5
            else "Cobertura fuerte y reutilizable."
            if adjusted_score == 4
            else "Cobertura moderada con evidencia visible."
            if adjusted_score == 3
            else "Cobertura minima o parcial."
            if adjusted_score == 2
            else "Sin evidencia suficiente en este frente."
        )
        uncertainty_note = (
            "El criterio tiene un sosten principal razonablemente claro."
            if adjusted_score >= 4
            else "El criterio depende de menos evidencia y puede necesitar confirmacion adicional."
            if adjusted_score >= 2
            else "El criterio queda debil o incierto para este frente."
        )
        criterion_result = {
            "criterion_id": criterion["criterion_id"],
            "label": criterion["label"],
            "weight": criterion["weight"],
            "matched_terms": matched_terms,
            "matched_term_count": len(matched_terms),
            "blocker_terms": blocker_terms,
            "blocker_count": len(blocker_terms),
            "line_hits": evidence_hits[:focus_limit],
            "supporting_sources": sorted(supporting_sources),
            "score": adjusted_score,
            "weighted_score": weighted_score,
            "short_assessment": short_assessment,
            "uncertainty_note": uncertainty_note,
        }
        criterion_results.append(criterion_result)
        overall_blockers.extend(blocker_terms)

    blocker_hits = []
    for source_record in evidence_records:
        terms, hits = collect_line_hits(source_record, front["blocking_signals"], focus_limit)
        for term in terms:
            if term not in blocker_hits:
                blocker_hits.append(term)
                overall_blockers.append(term)

    bucket_signal_hits = {}
    assigned_bucket = None
    for bucket_id in forced_bucket_order:
        terms = front["bucket_signal_terms"].get(bucket_id, [])
        if not terms:
            continue
        bucket_terms = []
        bucket_lines = []
        for source_record in evidence_records:
            found_terms, hits = collect_line_hits(source_record, terms, focus_limit)
            for term in found_terms:
                if term not in bucket_terms:
                    bucket_terms.append(term)
            for hit in hits:
                if hit not in bucket_lines:
                    bucket_lines.append(hit)
        if bucket_terms:
            bucket_signal_hits[bucket_id] = {
                "matched_terms": bucket_terms,
                "line_hits": bucket_lines[:focus_limit],
            }
            assigned_bucket = bucket_id
            break

    total_weighted = sum(item["weighted_score"] for item in criterion_results)
    cost_penalty = COST_PENALTY[front["relative_cost"]]
    blocker_penalty = min(8, len(set(overall_blockers)) * 2)
    priority_score = max(0, total_weighted - cost_penalty - blocker_penalty)

    if assigned_bucket is None:
        if priority_score >= bucket_map["NOW"]["min_score"] and len(blocker_hits) <= bucket_map["NOW"]["max_blocker_hits"]:
            assigned_bucket = "NOW"
        elif priority_score >= bucket_map["NEXT"]["min_score"] and len(blocker_hits) <= bucket_map["NEXT"]["max_blocker_hits"]:
            assigned_bucket = "NEXT"
        else:
            assigned_bucket = "LATER"

    button = bucket_map[assigned_bucket]["button"]
    button_reason = "seguir ahora" if button == "GREEN" else "no seguir ahora"
    front_results.append(
        {
            "front_id": front["front_id"],
            "label": front["label"],
            "description": front["description"],
            "current_state_hint": front["current_state_hint"],
            "intended_outcome": front["intended_outcome"],
            "priority_score": priority_score,
            "priority_bucket": assigned_bucket,
            "green_red_button": button,
            "button_reason": button_reason,
            "relative_cost": front["relative_cost"],
            "relative_cost_note": front["relative_cost_note"],
            "risk_hints": front["risk_hints"],
            "preconditions": front["preconditions"],
            "kill_criteria": front["kill_criteria"],
            "recommended_action": front["recommended_action"],
            "notes": front["notes"],
            "criteria_results": criterion_results,
            "public_evidence_summary": public_lines[:focus_limit],
            "local_state_summary": local_lines[:focus_limit],
            "blocking_signal_hits": sorted(set(blocker_hits)),
            "bucket_signal_hits": bucket_signal_hits,
        }
    )

ranked_fronts = sorted(front_results, key=lambda item: (-item["priority_score"], item["front_id"]))
for idx, front in enumerate(ranked_fronts, start=1):
    front["priority_rank"] = idx

by_bucket = {bucket["bucket_id"]: [] for bucket in manifest["priority_buckets"]}
for front in ranked_fronts:
    by_bucket[front["priority_bucket"]].append(front["front_id"])

active_fronts = [front for front in ranked_fronts if front["priority_bucket"] in ACTIVE_BUCKETS]
recommended_front = next((front for front in ranked_fronts if front["priority_bucket"] == "NOW"), None)
if recommended_front is None and active_fronts:
    recommended_front = active_fronts[0]
runner_up_front = None
if recommended_front is not None:
    for candidate in active_fronts:
        if candidate["front_id"] != recommended_front["front_id"]:
            runner_up_front = candidate
            break

uncertainties = []
for front in ranked_fronts:
    if not front["public_evidence_summary"]:
        uncertainties.append(f"{front['front_id']}: la evidencia publica es mas delgada que la evidencia local versionada.")
    if front["priority_bucket"] in {"REOPEN_ONLY_IF", "FROZEN", "DO_NOT_TOUCH"}:
        uncertainties.append(f"{front['front_id']}: el bucket depende de senales bloqueantes o verdades congeladas, no de expansion positiva.")
if recommended_front and runner_up_front:
    margin = recommended_front["priority_score"] - runner_up_front["priority_score"]
else:
    margin = recommended_front["priority_score"] if recommended_front else 0
confidence = "strong" if margin >= 12 else "moderate" if margin >= 5 else "narrow"

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-project-prioritization",
    "task_id": manifest["task_id"],
    "title": manifest["title"],
    "description": manifest["description"],
    "question": manifest["question"],
    "manifest_path": str(manifest_path),
    "focus_terms": manifest["focus_terms"],
    "expected_signals": manifest["expected_signals"],
    "public_sources": [
        {
            "label": item["label"],
            "url": item["url"],
            "notes": item["notes"],
            "artifact_json": item["artifact_json"],
            "artifact_markdown": item["artifact_markdown"],
            "title": item["extract"]["selection"]["title"],
            "line_count": item["extract"]["content"]["line_count"],
            "word_count": item["extract"]["content"]["word_count"],
            "excerpt_lines": item["extract"]["content"]["excerpt_lines"][:manifest["focus_profile"]["excerpt_limit"]],
        }
        for item in public_records
    ],
    "local_sources": [
        {
            "label": item["label"],
            "path": item["path"],
            "notes": item["notes"],
            "artifact_json": item["artifact_json"],
            "artifact_markdown": item["artifact_markdown"],
            "line_count": item["extract"]["content"]["line_count"],
            "word_count": item["extract"]["content"]["word_count"],
            "excerpt_lines": item["extract"]["content"]["excerpt_lines"][:manifest["focus_profile"]["excerpt_limit"]],
        }
        for item in local_records
    ],
    "priority_buckets": manifest["priority_buckets"],
    "project_fronts": ranked_fronts,
    "bucket_overview": by_bucket,
    "final_prioritization": {
        "recommended_front": {
            "front_id": recommended_front["front_id"],
            "label": recommended_front["label"],
            "priority_bucket": recommended_front["priority_bucket"],
            "priority_score": recommended_front["priority_score"],
            "recommended_action": recommended_front["recommended_action"],
        }
        if recommended_front
        else None,
        "runner_up_front": {
            "front_id": runner_up_front["front_id"],
            "label": runner_up_front["label"],
            "priority_bucket": runner_up_front["priority_bucket"],
            "priority_score": runner_up_front["priority_score"],
            "recommended_action": runner_up_front["recommended_action"],
        }
        if runner_up_front
        else None,
        "confidence": confidence,
        "margin_vs_runner_up": margin,
        "next_tranche_suggested": recommended_front["recommended_action"] if recommended_front else "",
        "uncertainties": uncertainties[:6],
    },
}

markdown = []
markdown.append(f"# Browser Sidecar Project Prioritization: {manifest['title']}")
markdown.append("")
markdown.append(f"generated_at: {payload['generated_at']}")
markdown.append(f"artifact_kind: {payload['artifact_kind']}")
markdown.append(f"task_id: {payload['task_id']}")
markdown.append(f"manifest_path: {payload['manifest_path']}")
markdown.append("")
markdown.append("## Question")
markdown.append(payload["question"])
markdown.append("")
markdown.append("## Public Sources")
for source in payload["public_sources"]:
    markdown.append(f"### {source['label']}")
    markdown.append(f"- url: {source['url']}")
    markdown.append(f"- line_count: {source['line_count']}")
    markdown.append(f"- word_count: {source['word_count']}")
    markdown.append(f"- artifact_json: {source['artifact_json']}")
    markdown.append(f"- artifact_markdown: {source['artifact_markdown']}")
    excerpt = source["excerpt_lines"][: manifest["focus_profile"]["excerpt_limit"]]
    if excerpt:
        markdown.append("- excerpt:")
        for line in excerpt:
            markdown.append(f"  - {line}")
    markdown.append("")
markdown.append("## Local Versioned Sources")
for source in payload["local_sources"]:
    markdown.append(f"### {source['label']}")
    markdown.append(f"- path: {source['path']}")
    markdown.append(f"- line_count: {source['line_count']}")
    markdown.append(f"- word_count: {source['word_count']}")
    markdown.append(f"- artifact_json: {source['artifact_json']}")
    markdown.append(f"- artifact_markdown: {source['artifact_markdown']}")
    excerpt = source["excerpt_lines"][: manifest["focus_profile"]["excerpt_limit"]]
    if excerpt:
        markdown.append("- excerpt:")
        for line in excerpt:
            markdown.append(f"  - {line}")
    markdown.append("")
markdown.append("## Priority Matrix")
for front in ranked_fronts:
    markdown.append(f"### {front['front_id']}")
    markdown.append(f"- label: {front['label']}")
    markdown.append(f"- priority_rank: {front['priority_rank']}")
    markdown.append(f"- priority_score: {front['priority_score']}")
    markdown.append(f"- priority_bucket: {front['priority_bucket']}")
    markdown.append(f"- green_red_button: {front['green_red_button']}")
    markdown.append(f"- button_reason: {front['button_reason']}")
    markdown.append(f"- relative_cost: {front['relative_cost']}")
    markdown.append(f"- current_state_hint: {front['current_state_hint']}")
    markdown.append(f"- intended_outcome: {front['intended_outcome']}")
    markdown.append(f"- recommended_action: {front['recommended_action']}")
    markdown.append("- public_evidence_summary:")
    if front["public_evidence_summary"]:
        for line in front["public_evidence_summary"]:
            markdown.append(f"  - {line}")
    else:
        markdown.append("  - (sin evidencia publica destacable en este frente)")
    markdown.append("- local_state_summary:")
    if front["local_state_summary"]:
        for line in front["local_state_summary"]:
            markdown.append(f"  - {line}")
    else:
        markdown.append("  - (sin evidencia local destacable en este frente)")
    markdown.append("- blocking_signal_hits:")
    if front["blocking_signal_hits"]:
        for line in front["blocking_signal_hits"]:
            markdown.append(f"  - {line}")
    else:
        markdown.append("  - (sin bloqueos explicitos detectados)")
    markdown.append("- risks:")
    for item in front["risk_hints"]:
        markdown.append(f"  - {item}")
    markdown.append("- preconditions:")
    for item in front["preconditions"]:
        markdown.append(f"  - {item}")
    markdown.append("- kill_criteria:")
    for item in front["kill_criteria"]:
        markdown.append(f"  - {item}")
    markdown.append("- criteria_strength:")
    for criterion in front["criteria_results"]:
        markdown.append(
            f"  - {criterion['criterion_id']}: score={criterion['score']}/5 weighted_score={criterion['weighted_score']} matched_terms={criterion['matched_term_count']} blocker_count={criterion['blocker_count']}"
        )
    if front["bucket_signal_hits"]:
        markdown.append("- bucket_signal_hits:")
        for bucket_id, bucket_info in front["bucket_signal_hits"].items():
            markdown.append(f"  - {bucket_id}: {', '.join(bucket_info['matched_terms'])}")
    markdown.append("")
markdown.append("## Bucket Overview")
for bucket in manifest["priority_buckets"]:
    bucket_id = bucket["bucket_id"]
    markdown.append(f"- {bucket_id}: {', '.join(by_bucket[bucket_id]) if by_bucket[bucket_id] else '(sin frentes)'}")
markdown.append("")
markdown.append("## Final Prioritization")
if recommended_front:
    markdown.append(f"- recommended_front: {recommended_front['front_id']}")
    markdown.append(f"- recommended_bucket: {recommended_front['priority_bucket']}")
    markdown.append(f"- suggested_next_tranche: {recommended_front['recommended_action']}")
if runner_up_front:
    markdown.append(f"- runner_up_front: {runner_up_front['front_id']}")
    markdown.append(f"- runner_up_bucket: {runner_up_front['priority_bucket']}")
markdown.append(f"- confidence: {confidence}")
markdown.append(f"- margin_vs_runner_up: {margin}")
markdown.append("- now_fronts:")
for item in by_bucket["NOW"] or ["(sin frentes NOW)"]:
    markdown.append(f"  - {item}")
markdown.append("- next_fronts:")
for item in by_bucket["NEXT"] or ["(sin frentes NEXT)"]:
    markdown.append(f"  - {item}")
markdown.append("- later_fronts:")
for item in by_bucket["LATER"] or ["(sin frentes LATER)"]:
    markdown.append(f"  - {item}")
markdown.append("- frozen_fronts:")
for item in by_bucket["FROZEN"] or ["(sin frentes FROZEN)"]:
    markdown.append(f"  - {item}")
markdown.append("- do_not_touch_fronts:")
for item in by_bucket["DO_NOT_TOUCH"] or ["(sin frentes DO_NOT_TOUCH)"]:
    markdown.append(f"  - {item}")
markdown.append("- reopen_only_if_fronts:")
for item in by_bucket["REOPEN_ONLY_IF"] or ["(sin frentes REOPEN_ONLY_IF)"]:
    markdown.append(f"  - {item}")
markdown.append("- uncertainties:")
for item in payload["final_prioritization"]["uncertainties"] or ["(sin incertidumbres destacadas)"]:
    markdown.append(f"  - {item}")
markdown.append("")
markdown_text = "\n".join(markdown) + "\n"

json_path = timestamped_path(final_slug, "json")
md_path = timestamped_path(final_slug, "md")
json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
md_path.write_text(markdown_text, encoding="utf-8")
subprocess.run([validate_markdown, str(md_path)], check=True, stdout=subprocess.DEVNULL)

print(f"PRIORITIZATION_FINAL_ARTIFACT_JSON {json_path.relative_to(repo_root)}", file=sys.stderr)
print(f"PRIORITIZATION_FINAL_ARTIFACT_MD {md_path.relative_to(repo_root)}", file=sys.stderr)

if output_format == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    print(markdown_text, end="")
PY
