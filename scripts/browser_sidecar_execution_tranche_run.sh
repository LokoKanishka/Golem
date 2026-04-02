#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_execution_tranche_run.sh [--format json|markdown] [--save-slug slug] <tranche-task.json>

Ejemplos:
  ./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-golem-openclaw-next-execution.json
  ./scripts/browser_sidecar_execution_tranche_run.sh --format json browser_tasks/tranche-project-evidence-maintenance-next-execution.json
  ./scripts/browser_sidecar_execution_tranche_run.sh --save-slug tranche-run browser_tasks/tranche-golem-openclaw-next-execution.json
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
EFFORT_PENALTY = {"low": 0, "medium": 3, "high": 6}
BUCKET_PRIORITY = {"NOW": 12, "NEXT": 8, "LATER": 4, "FROZEN": 0, "DO_NOT_TOUCH": 0, "REOPEN_ONLY_IF": 0}


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


def timestamped_path(slug: str, extension: str) -> Path:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return outbox_dir / f"{ts}_{slug}.{extension}"


def req_text(data: dict, name: str) -> str:
    value = str(data.get(name, "")).strip()
    if not value:
        raise SystemExit(f"ERROR: {name} no puede estar vacio")
    return value


def validate_sources(raw_sources: list[dict], key_name: str) -> tuple[list[dict], set[str]]:
    items = []
    labels = set()
    for idx, source in enumerate(raw_sources):
        if not isinstance(source, dict):
            raise SystemExit(f"ERROR: {key_name} {idx} no es un objeto")
        label = str(source.get("label", "")).strip()
        if not label:
            raise SystemExit(f"ERROR: {key_name} {idx} requiere label")
        if not slug_re.match(label):
            raise SystemExit(f"ERROR: label invalido en {key_name} {idx}: {label}")
        if label in labels:
            raise SystemExit(f"ERROR: label duplicado en {key_name}: {label}")
        labels.add(label)
        if key_name == "source":
            url = str(source.get("url", "")).strip()
            if not url:
                raise SystemExit(f"ERROR: source {idx} requiere url")
            items.append(
                {
                    "label": label,
                    "url": url,
                    "selector_hint": str(source.get("selector_hint", "")).strip(),
                    "notes": str(source.get("notes", "")).strip(),
                    "kind": "public",
                }
            )
        else:
            rel_path = str(source.get("path", "")).strip()
            if not rel_path:
                raise SystemExit(f"ERROR: local_source {idx} requiere path")
            abs_path = (repo_root / rel_path).resolve()
            if not abs_path.exists():
                raise SystemExit(f"ERROR: no existe local_source path: {rel_path}")
            items.append(
                {
                    "label": label,
                    "path": rel_path,
                    "abs_path": str(abs_path),
                    "notes": str(source.get("notes", "")).strip(),
                    "kind": "local",
                }
            )
    return items, labels


def load_manifest() -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = [
        "task_id",
        "title",
        "description",
        "question",
        "prioritization_task",
        "sources",
        "local_sources",
        "decision_criteria",
        "candidate_tranches",
    ]
    for key in required:
        if key not in data:
            raise SystemExit(f"ERROR: falta campo requerido en execution tranche manifest: {key}")

    task_id = req_text(data, "task_id")
    if not slug_re.match(task_id):
        raise SystemExit("ERROR: task_id invalido")
    output_slug = str(data.get("output_slug", task_id)).strip()
    if not slug_re.match(output_slug):
        raise SystemExit("ERROR: output_slug invalido")

    prioritization_task = str(data.get("prioritization_task", "")).strip()
    if not prioritization_task:
        raise SystemExit("ERROR: prioritization_task no puede estar vacio")
    prioritization_task_path = (repo_root / prioritization_task).resolve()
    if not prioritization_task_path.exists():
        raise SystemExit(f"ERROR: no existe prioritization_task: {prioritization_task}")

    focus_terms = [str(item).strip() for item in data.get("focus_terms", []) if str(item).strip()]
    expected_signals = [str(item).strip() for item in data.get("expected_signals", []) if str(item).strip()]
    focus_profile = data.get("focus_profile", {}) or {}
    excerpt_limit = int(focus_profile.get("excerpt_limit", 10))
    match_limit = int(focus_profile.get("match_limit", 3))
    if excerpt_limit <= 0 or match_limit <= 0:
        raise SystemExit("ERROR: focus_profile.excerpt_limit y match_limit deben ser enteros positivos")

    public_sources, public_labels = validate_sources(data["sources"], "source")
    local_sources, local_labels = validate_sources(data["local_sources"], "local_source")
    source_labels = public_labels | local_labels

    criteria = []
    criterion_ids = set()
    for idx, criterion in enumerate(data["decision_criteria"]):
        if not isinstance(criterion, dict):
            raise SystemExit(f"ERROR: decision_criteria {idx} no es un objeto")
        criterion_id = str(criterion.get("criterion_id", "")).strip()
        label = str(criterion.get("label", "")).strip()
        description = str(criterion.get("description", "")).strip()
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
                "notes": str(criterion.get("notes", "")).strip(),
            }
        )

    candidates = []
    tranche_ids = set()
    for idx, tranche in enumerate(data["candidate_tranches"]):
        if not isinstance(tranche, dict):
            raise SystemExit(f"ERROR: candidate_tranche {idx} no es un objeto")
        tranche_id = str(tranche.get("tranche_id", "")).strip()
        label = str(tranche.get("label", "")).strip()
        description = str(tranche.get("description", "")).strip()
        goal = str(tranche.get("goal", "")).strip()
        relative_effort = str(tranche.get("relative_effort", "")).strip().lower()
        relative_effort_note = str(tranche.get("relative_effort_note", "")).strip()
        notes = str(tranche.get("notes", "")).strip()
        if not tranche_id or not label or not description or not goal:
            raise SystemExit(f"ERROR: candidate_tranche {idx} requiere tranche_id/label/description/goal")
        if not slug_re.match(tranche_id):
            raise SystemExit(f"ERROR: tranche_id invalido: {tranche_id}")
        if tranche_id in tranche_ids:
            raise SystemExit(f"ERROR: tranche_id duplicado: {tranche_id}")
        tranche_ids.add(tranche_id)
        if relative_effort not in EFFORT_PENALTY:
            raise SystemExit(f"ERROR: relative_effort invalido para tranche {tranche_id}")

        evidence_sources = [str(item).strip() for item in tranche.get("evidence_sources", []) if str(item).strip()]
        supporting_fronts = [str(item).strip() for item in tranche.get("supporting_fronts", []) if str(item).strip()]
        in_scope = [str(item).strip() for item in tranche.get("in_scope", []) if str(item).strip()]
        out_of_scope = [str(item).strip() for item in tranche.get("out_of_scope", []) if str(item).strip()]
        acceptance_criteria = [str(item).strip() for item in tranche.get("acceptance_criteria", []) if str(item).strip()]
        preconditions = [str(item).strip() for item in tranche.get("preconditions", []) if str(item).strip()]
        risk_hints = [str(item).strip() for item in tranche.get("risk_hints", []) if str(item).strip()]
        kill_criteria = [str(item).strip() for item in tranche.get("kill_criteria", []) if str(item).strip()]
        required_artifacts = [str(item).strip() for item in tranche.get("required_artifacts", []) if str(item).strip()]
        verify_requirements = [str(item).strip() for item in tranche.get("verify_requirements", []) if str(item).strip()]
        if not evidence_sources or not supporting_fronts:
            raise SystemExit(f"ERROR: tranche {tranche_id} requiere evidence_sources y supporting_fronts")
        if not in_scope or not out_of_scope or not acceptance_criteria:
            raise SystemExit(f"ERROR: tranche {tranche_id} requiere in_scope, out_of_scope y acceptance_criteria")
        if not preconditions or not risk_hints or not kill_criteria:
            raise SystemExit(f"ERROR: tranche {tranche_id} requiere preconditions, risk_hints y kill_criteria")
        if not required_artifacts or not verify_requirements:
            raise SystemExit(f"ERROR: tranche {tranche_id} requiere required_artifacts y verify_requirements")
        for source_label in evidence_sources:
            if source_label not in source_labels:
                raise SystemExit(f"ERROR: tranche {tranche_id} referencia evidence_source inexistente: {source_label}")

        ticket_seed = tranche.get("implementation_ticket_seed", {}) or {}
        ticket_title = str(ticket_seed.get("title", "")).strip()
        ticket_summary = str(ticket_seed.get("summary", "")).strip()
        ticket_deliverables = [str(item).strip() for item in ticket_seed.get("deliverables", []) if str(item).strip()]
        ticket_verify = [str(item).strip() for item in ticket_seed.get("verify", []) if str(item).strip()]
        if not ticket_title or not ticket_summary or not ticket_deliverables or not ticket_verify:
            raise SystemExit(f"ERROR: tranche {tranche_id} requiere implementation_ticket_seed completo")

        candidates.append(
            {
                "tranche_id": tranche_id,
                "label": label,
                "description": description,
                "goal": goal,
                "supporting_fronts": supporting_fronts,
                "evidence_sources": evidence_sources,
                "relative_effort": relative_effort,
                "relative_effort_note": relative_effort_note,
                "in_scope": in_scope,
                "out_of_scope": out_of_scope,
                "acceptance_criteria": acceptance_criteria,
                "preconditions": preconditions,
                "risk_hints": risk_hints,
                "kill_criteria": kill_criteria,
                "required_artifacts": required_artifacts,
                "verify_requirements": verify_requirements,
                "notes": notes,
                "implementation_ticket_seed": {
                    "title": ticket_title,
                    "summary": ticket_summary,
                    "deliverables": ticket_deliverables,
                    "verify": ticket_verify,
                },
            }
        )

    return {
        "task_kind": "execution_tranche",
        "task_id": task_id,
        "title": req_text(data, "title"),
        "description": req_text(data, "description"),
        "question": req_text(data, "question"),
        "output_slug": output_slug,
        "prioritization_task": prioritization_task,
        "prioritization_task_path": str(prioritization_task_path),
        "focus_terms": focus_terms,
        "expected_signals": expected_signals,
        "focus_profile": {
            "excerpt_limit": excerpt_limit,
            "match_limit": match_limit,
        },
        "sources": public_sources,
        "local_sources": local_sources,
        "decision_criteria": criteria,
        "candidate_tranches": candidates,
        "manifest_path": str(manifest_path),
    }


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
    markdown = [
        f"# Browser Sidecar Local Extract: {source['label']}",
        "",
        f"generated_at: {payload['generated_at']}",
        f"artifact_kind: {payload['artifact_kind']}",
        f"source_kind: {payload['source_kind']}",
        f"source_path: {source['path']}",
        f"title: {source['label']}",
        "",
        "## Summary",
        f"- line_count: {payload['content']['line_count']}",
        f"- unique_line_count: {payload['content']['unique_line_count']}",
        f"- word_count: {payload['content']['word_count']}",
        f"- link_count: {payload['content']['link_count']}",
        "",
        "## Excerpt",
    ]
    excerpt = payload["content"]["excerpt_lines"] or ["(sin lineas visibles)"]
    markdown.extend(f"- {line}" for line in excerpt)
    markdown.extend(["", "## Text"])
    markdown.extend(f"- {line}" for line in payload["content"]["text_lines"] or ["(sin texto)"])
    markdown.extend(["", "## Links"])
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
    return {
        "label": source["label"],
        "kind": "local",
        "path": source["path"],
        "notes": source["notes"],
        "artifact_json": str(json_path.relative_to(repo_root)),
        "artifact_markdown": str(md_path.relative_to(repo_root)),
        "extract": payload,
    }


def make_public_fallback_extract(source: dict, base_payload: dict, final_slug: str, sidecar_json: str, sidecar_md: str) -> dict:
    html_response = subprocess.run(["curl", "-fsSL", source["url"]], check=True, text=True, capture_output=True)
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
    markdown = [
        f"# Browser Sidecar Public Fallback Extract: {title}",
        "",
        f"generated_at: {payload['generated_at']}",
        f"artifact_kind: {payload['artifact_kind']}",
        f"source_kind: {payload['source_kind']}",
        f"url: {source['url']}",
        f"sidecar_artifact_json: {sidecar_json}",
        f"sidecar_artifact_markdown: {sidecar_md}",
        "",
        "## Summary",
        f"- line_count: {payload['content']['line_count']}",
        f"- word_count: {payload['content']['word_count']}",
        "",
        "## Excerpt",
    ]
    markdown.extend(f"- {line}" for line in payload["content"]["excerpt_lines"] or ["(sin lineas visibles)"])
    markdown.extend(["", "## Text"])
    markdown.extend(f"- {line}" for line in payload["content"]["text_lines"] or ["(sin texto)"])
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
    selector = str(resolved.get("index", source["selector_hint"] or source["label"]))
    completed = subprocess.run(
        [
            str(script_dir / "browser_sidecar_extract.sh"),
            "--format",
            "json",
            "--save-slug",
            slug,
            selector,
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    payload = json.loads(completed.stdout)
    json_match = re.findall(r"^EXTRACT_ARTIFACT_JSON (.+)$", completed.stderr, flags=re.MULTILINE)
    md_match = re.findall(r"^EXTRACT_ARTIFACT_MD (.+)$", completed.stderr, flags=re.MULTILINE)
    if not json_match or not md_match:
        raise SystemExit(f"ERROR: no se pudieron detectar artefactos para source {source['label']}")
    sidecar_json = json_match[-1].strip()
    sidecar_md = md_match[-1].strip()
    if payload["content"]["line_count"] == 0:
        return make_public_fallback_extract(source, payload, final_slug, sidecar_json, sidecar_md)
    return {
        "label": source["label"],
        "kind": "public",
        "url": source["url"],
        "selector_hint": source["selector_hint"],
        "notes": source["notes"],
        "artifact_json": sidecar_json,
        "artifact_markdown": sidecar_md,
        "extract": payload,
    }


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


def collect_text_hits(lines: list[str], source_label: str, source_kind: str, terms: list[str], limit: int) -> tuple[list[str], list[dict]]:
    matched_terms = []
    hits = []
    for term in terms:
        needle = term.lower()
        found = False
        for idx, line in enumerate(lines, start=1):
            if needle in line.lower():
                matched_terms.append(term)
                hits.append(
                    {
                        "source_label": source_label,
                        "source_kind": source_kind,
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


def front_context_lines(front: dict) -> list[str]:
    lines = [
        front.get("label", ""),
        front.get("description", ""),
        front.get("current_state_hint", ""),
        front.get("intended_outcome", ""),
        front.get("recommended_action", ""),
        front.get("priority_bucket", ""),
        front.get("button_reason", ""),
    ]
    lines.extend(front.get("public_evidence_summary", []))
    lines.extend(front.get("local_state_summary", []))
    lines.extend(front.get("risk_hints", []))
    lines.extend(front.get("preconditions", []))
    lines.extend(front.get("kill_criteria", []))
    return [normalize_text_line(item) for item in lines if normalize_text_line(item)]


def compute_priority_strength(fronts: list[dict]) -> tuple[int, str]:
    if not fronts:
        return 0, "sin frentes de respaldo"
    score = 0
    summary_parts = []
    for idx, front in enumerate(sorted(fronts, key=lambda item: (-item["priority_score"], item["front_id"]))):
        bucket = front["priority_bucket"]
        base = BUCKET_PRIORITY.get(bucket, 0)
        score += base if idx == 0 else max(0, base // 2)
        summary_parts.append(f'{front["front_id"]}:{bucket}')
    return score, ", ".join(summary_parts)


def summarize_non_winner(candidate: dict, winner: dict) -> str:
    reasons = []
    if candidate["priority_strength_score"] < winner["priority_strength_score"]:
        reasons.append("hereda buckets mas debiles desde la priorizacion")
    if candidate["relative_effort"] != winner["relative_effort"]:
        if EFFORT_PENALTY[candidate["relative_effort"]] > EFFORT_PENALTY[winner["relative_effort"]]:
            reasons.append("pide mas esfuerzo relativo")
    if candidate["blocker_hits"]:
        reasons.append("arrastra mas senales de bloqueo")
    if not candidate["public_evidence_summary"]:
        reasons.append("tiene evidencia publica menos clara")
    if not reasons:
        reasons.append("queda por debajo en margen global y claridad operativa")
    return "; ".join(reasons)


manifest = load_manifest()
final_slug = save_slug_override.strip() or manifest["output_slug"]
if not slug_re.match(final_slug):
    raise SystemExit("ERROR: save_slug invalido")

prioritization_slug = f"{final_slug}_prioritization"
prioritization_completed = subprocess.run(
    [
        str(script_dir / "browser_sidecar_prioritization_run.sh"),
        "--format",
        "json",
        "--save-slug",
        prioritization_slug,
        manifest["prioritization_task_path"],
    ],
    check=True,
    text=True,
    capture_output=True,
)
prioritization_payload = json.loads(prioritization_completed.stdout)
prior_json_match = re.findall(r"^PRIORITIZATION_FINAL_ARTIFACT_JSON (.+)$", prioritization_completed.stderr, flags=re.MULTILINE)
prior_md_match = re.findall(r"^PRIORITIZATION_FINAL_ARTIFACT_MD (.+)$", prioritization_completed.stderr, flags=re.MULTILINE)
if not prior_json_match or not prior_md_match:
    raise SystemExit("ERROR: no se pudieron detectar los artefactos del prioritization lane")
prioritization_json_artifact = prior_json_match[-1].strip()
prioritization_md_artifact = prior_md_match[-1].strip()

public_records = [run_public_extract(source, final_slug) for source in manifest["sources"]]
local_records = [make_local_extract(source, final_slug) for source in manifest["local_sources"]]
source_map = {item["label"]: item for item in public_records + local_records}
front_map = {front["front_id"]: front for front in prioritization_payload["project_fronts"]}

for tranche in manifest["candidate_tranches"]:
    for front_id in tranche["supporting_fronts"]:
        if front_id not in front_map:
            raise SystemExit(f"ERROR: tranche {tranche['tranche_id']} referencia supporting_front inexistente: {front_id}")

focus_limit = manifest["focus_profile"]["match_limit"]
excerpt_limit = manifest["focus_profile"]["excerpt_limit"]
criteria = manifest["decision_criteria"]

tranche_results = []
for tranche in manifest["candidate_tranches"]:
    evidence_records = [source_map[label] for label in tranche["evidence_sources"]]
    supporting_fronts = [front_map[front_id] for front_id in tranche["supporting_fronts"]]
    criterion_results = []
    public_lines = []
    local_lines = []
    upstream_lines = []
    blocker_hits = []

    for criterion in criteria:
        matched_terms = []
        evidence_hits = []
        criterion_blockers = []
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
                b_terms, _ = collect_line_hits(source_record, criterion["blocker_terms"], focus_limit)
                for term in b_terms:
                    if term not in criterion_blockers:
                        criterion_blockers.append(term)

        for front in supporting_fronts:
            front_lines = front_context_lines(front)
            terms, hits = collect_text_hits(front_lines, front["front_id"], "upstream_prioritization", criterion["evidence_terms"], focus_limit)
            for term in terms:
                if term not in matched_terms:
                    matched_terms.append(term)
            for hit in hits:
                if hit not in evidence_hits:
                    evidence_hits.append(hit)
                supporting_sources.add(front["front_id"])
                if hit["line"] not in upstream_lines:
                    upstream_lines.append(hit["line"])
            if criterion["blocker_terms"]:
                b_terms, _ = collect_text_hits(front_lines, front["front_id"], "upstream_prioritization", criterion["blocker_terms"], focus_limit)
                for term in b_terms:
                    if term not in criterion_blockers:
                        criterion_blockers.append(term)

        raw_score = score_from_matches(len(matched_terms))
        adjusted_score = max(0, raw_score - min(2, len(criterion_blockers)))
        weighted_score = adjusted_score * criterion["weight"]
        short_assessment = (
            "Cobertura muy fuerte con cierre operativo visible."
            if adjusted_score >= 5
            else "Cobertura fuerte y defendible."
            if adjusted_score == 4
            else "Cobertura moderada con evidencia visible."
            if adjusted_score == 3
            else "Cobertura minima o parcial."
            if adjusted_score == 2
            else "Sin evidencia suficiente para defender este criterio."
        )
        criterion_results.append(
            {
                "criterion_id": criterion["criterion_id"],
                "label": criterion["label"],
                "weight": criterion["weight"],
                "matched_terms": matched_terms,
                "matched_term_count": len(matched_terms),
                "blocker_terms": criterion_blockers,
                "blocker_count": len(criterion_blockers),
                "line_hits": evidence_hits[:focus_limit],
                "supporting_sources": sorted(supporting_sources),
                "score": adjusted_score,
                "weighted_score": weighted_score,
                "short_assessment": short_assessment,
            }
        )
        for term in criterion_blockers:
            if term not in blocker_hits:
                blocker_hits.append(term)

    priority_strength_score, priority_strength_summary = compute_priority_strength(supporting_fronts)
    frozen_support = [front["front_id"] for front in supporting_fronts if front["priority_bucket"] in {"FROZEN", "DO_NOT_TOUCH", "REOPEN_ONLY_IF"}]
    for front_id in frozen_support:
        blocker_hits.append(front_id)
    blocker_hits = sorted(set(blocker_hits))
    weighted_total = sum(item["weighted_score"] for item in criterion_results)
    effort_penalty = EFFORT_PENALTY[tranche["relative_effort"]]
    blocker_penalty = min(8, len(blocker_hits) * 2)
    execution_score = max(0, weighted_total + priority_strength_score - effort_penalty - blocker_penalty)

    tranche_results.append(
        {
            "tranche_id": tranche["tranche_id"],
            "label": tranche["label"],
            "description": tranche["description"],
            "goal": tranche["goal"],
            "supporting_fronts": [
                {
                    "front_id": front["front_id"],
                    "label": front["label"],
                    "priority_bucket": front["priority_bucket"],
                    "priority_score": front["priority_score"],
                    "recommended_action": front["recommended_action"],
                }
                for front in supporting_fronts
            ],
            "priority_strength": priority_strength_summary,
            "priority_strength_score": priority_strength_score,
            "public_evidence_summary": public_lines[:excerpt_limit],
            "local_state_summary": local_lines[:excerpt_limit],
            "upstream_front_summary": upstream_lines[:excerpt_limit],
            "risk_summary": tranche["risk_hints"],
            "preconditions_summary": tranche["preconditions"],
            "kill_criteria_summary": tranche["kill_criteria"],
            "expected_artifacts_summary": tranche["required_artifacts"],
            "verify_readiness_summary": tranche["verify_requirements"],
            "acceptance_criteria": tranche["acceptance_criteria"],
            "in_scope": tranche["in_scope"],
            "out_of_scope": tranche["out_of_scope"],
            "relative_effort": tranche["relative_effort"],
            "relative_effort_note": tranche["relative_effort_note"],
            "blocker_hits": blocker_hits,
            "criteria_results": criterion_results,
            "implementation_ticket_seed": tranche["implementation_ticket_seed"],
            "notes": tranche["notes"],
            "execution_score": execution_score,
        }
    )

ranked_tranches = sorted(
    tranche_results,
    key=lambda item: (
        -item["execution_score"],
        -item["priority_strength_score"],
        EFFORT_PENALTY[item["relative_effort"]],
        item["tranche_id"],
    ),
)
for idx, tranche in enumerate(ranked_tranches, start=1):
    tranche["execution_rank"] = idx

winner = ranked_tranches[0] if ranked_tranches else None
runner_up = ranked_tranches[1] if len(ranked_tranches) > 1 else None
margin = (winner["execution_score"] - runner_up["execution_score"]) if winner and runner_up else (winner["execution_score"] if winner else 0)
confidence = "strong" if margin >= 12 else "moderate" if margin >= 5 else "narrow"

frozen_context = {
    "now_fronts": prioritization_payload["bucket_overview"].get("NOW", []),
    "next_fronts": prioritization_payload["bucket_overview"].get("NEXT", []),
    "later_fronts": prioritization_payload["bucket_overview"].get("LATER", []),
    "frozen_fronts": prioritization_payload["bucket_overview"].get("FROZEN", []),
    "do_not_touch_fronts": prioritization_payload["bucket_overview"].get("DO_NOT_TOUCH", []),
    "reopen_only_if_fronts": prioritization_payload["bucket_overview"].get("REOPEN_ONLY_IF", []),
}

why_now = []
why_not_others = []
if winner:
    why_now.append(f"Hereda prioridad desde {winner['priority_strength']}.")
    if winner["public_evidence_summary"]:
        why_now.append("Tiene evidencia publica visible suficiente para defender el arranque sin tocar runtime.")
    if winner["local_state_summary"]:
        why_now.append("Alinea el tramo con estado local versionado y limites ya aceptados.")
    top_criteria = sorted(winner["criteria_results"], key=lambda item: (-item["weighted_score"], item["criterion_id"]))[:2]
    for criterion in top_criteria:
        if criterion["weighted_score"] > 0:
            why_now.append(f"{criterion['label']} aporta {criterion['weighted_score']} puntos ponderados.")

for candidate in ranked_tranches[1:]:
    why_not_others.append(
        {
            "tranche_id": candidate["tranche_id"],
            "reason": summarize_non_winner(candidate, winner),
        }
    )

selected_ticket_seed = winner["implementation_ticket_seed"] if winner else None
final_brief = {
    "selected_tranche": {
        "tranche_id": winner["tranche_id"],
        "label": winner["label"],
        "goal": winner["goal"],
        "execution_score": winner["execution_score"],
        "execution_rank": winner["execution_rank"],
        "priority_strength": winner["priority_strength"],
        "in_scope": winner["in_scope"],
        "out_of_scope": winner["out_of_scope"],
        "acceptance_criteria": winner["acceptance_criteria"],
        "required_artifacts": winner["expected_artifacts_summary"],
        "verify_requirements": winner["verify_readiness_summary"],
        "risks": winner["risk_summary"],
        "preconditions": winner["preconditions_summary"],
        "kill_criteria": winner["kill_criteria_summary"],
        "supporting_fronts": winner["supporting_fronts"],
        "why_now": why_now,
        "implementation_ticket_seed": selected_ticket_seed,
    }
    if winner
    else None,
    "runner_up": {
        "tranche_id": runner_up["tranche_id"],
        "label": runner_up["label"],
        "goal": runner_up["goal"],
        "execution_score": runner_up["execution_score"],
        "execution_rank": runner_up["execution_rank"],
        "priority_strength": runner_up["priority_strength"],
    }
    if runner_up
    else None,
    "why_not_others": why_not_others,
    "confidence": confidence,
    "margin_vs_runner_up": margin,
    "frozen_context": frozen_context,
    "rationale": why_now,
}

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-execution-tranche",
    "task_id": manifest["task_id"],
    "title": manifest["title"],
    "description": manifest["description"],
    "question": manifest["question"],
    "manifest_path": str(manifest_path),
    "focus_terms": manifest["focus_terms"],
    "expected_signals": manifest["expected_signals"],
    "upstream_prioritization": {
        "task_manifest": manifest["prioritization_task"],
        "artifact_json": prioritization_json_artifact,
        "artifact_markdown": prioritization_md_artifact,
        "recommended_front": prioritization_payload["final_prioritization"]["recommended_front"],
        "runner_up_front": prioritization_payload["final_prioritization"]["runner_up_front"],
        "bucket_overview": prioritization_payload["bucket_overview"],
    },
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
            "excerpt_lines": item["extract"]["content"]["excerpt_lines"][:excerpt_limit],
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
            "excerpt_lines": item["extract"]["content"]["excerpt_lines"][:excerpt_limit],
        }
        for item in local_records
    ],
    "tranche_selection_matrix": ranked_tranches,
    "final_execution_brief": final_brief,
}

markdown = []
markdown.append(f"# Browser Sidecar Execution Tranche: {manifest['title']}")
markdown.append("")
markdown.append(f"generated_at: {payload['generated_at']}")
markdown.append(f"artifact_kind: {payload['artifact_kind']}")
markdown.append(f"task_id: {payload['task_id']}")
markdown.append(f"manifest_path: {payload['manifest_path']}")
markdown.append("")
markdown.append("## Question")
markdown.append(payload["question"])
markdown.append("")
markdown.append("## Upstream Prioritization")
markdown.append(f"- task_manifest: {manifest['prioritization_task']}")
markdown.append(f"- artifact_json: {prioritization_json_artifact}")
markdown.append(f"- artifact_markdown: {prioritization_md_artifact}")
if payload["upstream_prioritization"]["recommended_front"]:
    markdown.append(f"- recommended_front: {payload['upstream_prioritization']['recommended_front']['front_id']}")
if payload["upstream_prioritization"]["runner_up_front"]:
    markdown.append(f"- runner_up_front: {payload['upstream_prioritization']['runner_up_front']['front_id']}")
markdown.append("")
markdown.append("## Public Sources")
for source in payload["public_sources"]:
    markdown.append(f"### {source['label']}")
    markdown.append(f"- url: {source['url']}")
    markdown.append(f"- line_count: {source['line_count']}")
    markdown.append(f"- word_count: {source['word_count']}")
    markdown.append(f"- artifact_json: {source['artifact_json']}")
    markdown.append(f"- artifact_markdown: {source['artifact_markdown']}")
    markdown.append("- excerpt:")
    for line in source["excerpt_lines"] or ["(sin excerpt)"]:
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
    markdown.append("- excerpt:")
    for line in source["excerpt_lines"] or ["(sin excerpt)"]:
        markdown.append(f"  - {line}")
    markdown.append("")
markdown.append("## Tranche Selection Matrix")
for tranche in ranked_tranches:
    markdown.append(f"### {tranche['tranche_id']}")
    markdown.append(f"- label: {tranche['label']}")
    markdown.append(f"- execution_rank: {tranche['execution_rank']}")
    markdown.append(f"- execution_score: {tranche['execution_score']}")
    markdown.append(f"- priority_strength: {tranche['priority_strength']}")
    markdown.append(f"- relative_effort: {tranche['relative_effort']}")
    if tranche["relative_effort_note"]:
        markdown.append(f"- relative_effort_note: {tranche['relative_effort_note']}")
    markdown.append(f"- goal: {tranche['goal']}")
    markdown.append("- supporting_fronts:")
    for front in tranche["supporting_fronts"]:
        markdown.append(f"  - {front['front_id']} :: {front['priority_bucket']} :: {front['recommended_action']}")
    markdown.append("- public_evidence_summary:")
    for item in tranche["public_evidence_summary"] or ["(sin evidencia publica destacable)"]:
        markdown.append(f"  - {item}")
    markdown.append("- local_state_summary:")
    for item in tranche["local_state_summary"] or ["(sin evidencia local destacable)"]:
        markdown.append(f"  - {item}")
    markdown.append("- upstream_front_summary:")
    for item in tranche["upstream_front_summary"] or ["(sin evidencia upstream destacable)"]:
        markdown.append(f"  - {item}")
    markdown.append("- in_scope:")
    for item in tranche["in_scope"]:
        markdown.append(f"  - {item}")
    markdown.append("- out_of_scope:")
    for item in tranche["out_of_scope"]:
        markdown.append(f"  - {item}")
    markdown.append("- acceptance_criteria:")
    for item in tranche["acceptance_criteria"]:
        markdown.append(f"  - {item}")
    markdown.append("- required_artifacts:")
    for item in tranche["expected_artifacts_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- verify_requirements:")
    for item in tranche["verify_readiness_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- risks:")
    for item in tranche["risk_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- preconditions:")
    for item in tranche["preconditions_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- kill_criteria:")
    for item in tranche["kill_criteria_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- blocker_hits:")
    for item in tranche["blocker_hits"] or ["(sin bloqueos explicitos)"]:
        markdown.append(f"  - {item}")
    markdown.append("- criteria_strength:")
    for criterion in tranche["criteria_results"]:
        markdown.append(
            f"  - {criterion['criterion_id']}: score={criterion['score']}/5 weighted_score={criterion['weighted_score']} matched_terms={criterion['matched_term_count']} blocker_count={criterion['blocker_count']}"
        )
    markdown.append("")
markdown.append("## Frozen Context")
markdown.append("- now_fronts:")
for item in frozen_context["now_fronts"] or ["(sin frentes NOW)"]:
    markdown.append(f"  - {item}")
markdown.append("- next_fronts:")
for item in frozen_context["next_fronts"] or ["(sin frentes NEXT)"]:
    markdown.append(f"  - {item}")
markdown.append("- later_fronts:")
for item in frozen_context["later_fronts"] or ["(sin frentes LATER)"]:
    markdown.append(f"  - {item}")
markdown.append("- frozen_fronts:")
for item in frozen_context["frozen_fronts"] or ["(sin frentes FROZEN)"]:
    markdown.append(f"  - {item}")
markdown.append("- do_not_touch_fronts:")
for item in frozen_context["do_not_touch_fronts"] or ["(sin frentes DO_NOT_TOUCH)"]:
    markdown.append(f"  - {item}")
markdown.append("- reopen_only_if_fronts:")
for item in frozen_context["reopen_only_if_fronts"] or ["(sin frentes REOPEN_ONLY_IF)"]:
    markdown.append(f"  - {item}")
markdown.append("")
markdown.append("## Final Execution Brief")
if winner:
    markdown.append(f"- selected_tranche: {winner['tranche_id']}")
    markdown.append(f"- selected_goal: {winner['goal']}")
    markdown.append(f"- selected_score: {winner['execution_score']}")
    markdown.append(f"- selected_priority_strength: {winner['priority_strength']}")
if runner_up:
    markdown.append(f"- runner_up: {runner_up['tranche_id']}")
    markdown.append(f"- runner_up_score: {runner_up['execution_score']}")
markdown.append(f"- confidence: {confidence}")
markdown.append(f"- margin_vs_runner_up: {margin}")
markdown.append("- why_now:")
for item in why_now or ["(sin rationale adicional)"]:
    markdown.append(f"  - {item}")
markdown.append("- why_not_others:")
for item in why_not_others or [{"tranche_id": "(sin otros)", "reason": "no hay otros candidates"}]:
    markdown.append(f"  - {item['tranche_id']}: {item['reason']}")
if winner:
    markdown.append("- in_scope:")
    for item in winner["in_scope"]:
        markdown.append(f"  - {item}")
    markdown.append("- out_of_scope:")
    for item in winner["out_of_scope"]:
        markdown.append(f"  - {item}")
    markdown.append("- acceptance_criteria:")
    for item in winner["acceptance_criteria"]:
        markdown.append(f"  - {item}")
    markdown.append("- required_artifacts:")
    for item in winner["expected_artifacts_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- verify_requirements:")
    for item in winner["verify_readiness_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- risks:")
    for item in winner["risk_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- preconditions:")
    for item in winner["preconditions_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- kill_criteria:")
    for item in winner["kill_criteria_summary"]:
        markdown.append(f"  - {item}")
    markdown.append("- implementation_ticket_seed:")
    markdown.append(f"  - title: {winner['implementation_ticket_seed']['title']}")
    markdown.append(f"  - summary: {winner['implementation_ticket_seed']['summary']}")
    markdown.append("  - deliverables:")
    for item in winner["implementation_ticket_seed"]["deliverables"]:
        markdown.append(f"    - {item}")
    markdown.append("  - verify:")
    for item in winner["implementation_ticket_seed"]["verify"]:
        markdown.append(f"    - {item}")
markdown_text = "\n".join(markdown) + "\n"

json_path = timestamped_path(final_slug, "json")
md_path = timestamped_path(final_slug, "md")
json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
md_path.write_text(markdown_text, encoding="utf-8")
subprocess.run([validate_markdown, str(md_path)], check=True, stdout=subprocess.DEVNULL)

print(f"EXECUTION_TRANCHE_FINAL_ARTIFACT_JSON {json_path.relative_to(repo_root)}", file=sys.stderr)
print(f"EXECUTION_TRANCHE_FINAL_ARTIFACT_MD {md_path.relative_to(repo_root)}", file=sys.stderr)

if output_format == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    print(markdown_text, end="")
PY
