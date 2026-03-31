#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_extract.sh [--format json|markdown] [--save-slug slug] [target]

Ejemplos:
  ./scripts/browser_sidecar_extract.sh "Reserved Domains"
  ./scripts/browser_sidecar_extract.sh --format json rfc-editor.org
  ./scripts/browser_sidecar_extract.sh --save-slug browser-sidecar-iana "Reserved Domains"
USAGE
}

format="markdown"
save_slug=""
target=""

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
      save_slug="${2:-}"
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
      if [ -n "$target" ]; then
        printf 'ERROR: target extra no esperado: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      target="$1"
      shift
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  printf 'ERROR: argumentos extra no esperados\n' >&2
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

if [ -n "$save_slug" ]; then
  browser_sidecar_validate_slug "$save_slug"
fi

browser_sidecar_require_running

selector_input="$target"
if [ -n "$target" ] && browser_sidecar_looks_like_url "$target"; then
  browser_sidecar_run_tool open "$target" >/dev/null
  sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"
  selector_input=""
fi

selection_json="$(browser_sidecar_resolve_selector_json "$selector_input")"
selection_index="$(python3 - <<'PY' "$selection_json"
import json
import sys
print(json.loads(sys.argv[1])["index"])
PY
)"

snapshot_raw="$(browser_sidecar_run_tool snapshot "$selection_index")"

json_output="$(python3 - <<'PY' "$selection_json" "$target" "$selection_index" "$snapshot_raw"
import json
import re
import sys
from datetime import datetime, timezone

selection = json.loads(sys.argv[1])
target_input = sys.argv[2]
selection_index = int(sys.argv[3])
snapshot_raw = sys.argv[4]

text_lines = []
links = []
captured_at = ""
snapshot_selector = ""
snapshot_title = ""
snapshot_url = ""
section = None

def normalize(line: str) -> str:
    return " ".join(line.strip().split())

for raw_line in snapshot_raw.splitlines():
    line = raw_line.rstrip("\n")
    if line.startswith("captured_at: "):
        captured_at = line.split(": ", 1)[1]
        continue
    if line.startswith("selector: "):
        snapshot_selector = line.split(": ", 1)[1]
        continue
    if line.startswith("title: "):
        snapshot_title = line.split(": ", 1)[1]
        continue
    if line.startswith("url: "):
        snapshot_url = line.split(": ", 1)[1]
        continue
    if line == "## Text":
        section = "text"
        continue
    if line == "## Links":
        section = "links"
        continue
    if not line.startswith("- "):
        continue

    payload = normalize(line[2:])
    if not payload:
        continue

    if section == "text":
        text_lines.append(payload)
        continue
    if section == "links":
        if " :: " in payload:
          text, url = payload.split(" :: ", 1)
        else:
          text, url = payload, ""
        links.append({"text": text, "url": url})

visible_text = "\n".join(text_lines)
word_count = sum(len(re.findall(r"\S+", line)) for line in text_lines)
unique_lines = []
seen = set()
for line in text_lines:
    if line in seen:
        continue
    seen.add(line)
    unique_lines.append(line)

data = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-extract",
    "target_input": target_input,
    "selection": {
        "match_type": selection.get("match_type", ""),
        "index": selection_index,
        "title": selection.get("title", ""),
        "url": selection.get("url", ""),
        "id": selection.get("id", ""),
    },
    "snapshot": {
        "captured_at": captured_at,
        "selector": snapshot_selector,
        "title": snapshot_title,
        "url": snapshot_url,
    },
    "content": {
        "line_count": len(text_lines),
        "unique_line_count": len(unique_lines),
        "word_count": word_count,
        "excerpt_lines": text_lines[:12],
        "text_lines": text_lines,
        "normalized_text": visible_text,
        "links": links,
        "link_count": len(links),
    },
}

print(json.dumps(data, ensure_ascii=False, indent=2))
PY
)"

markdown_output="$(python3 - <<'PY' "$json_output"
import json
import sys

payload = json.loads(sys.argv[1])
selection = payload["selection"]
snapshot = payload["snapshot"]
content = payload["content"]

print(f"# Browser Sidecar Extract: {selection['title'] or snapshot['title'] or 'untitled'}")
print()
print(f"generated_at: {payload['generated_at']}")
print(f"artifact_kind: {payload['artifact_kind']}")
print(f"target_input: {payload['target_input'] or '(default)'}")
print(f"match_type: {selection['match_type']}")
print(f"selection_index: {selection['index']}")
print(f"title: {selection['title']}")
print(f"url: {selection['url']}")
print(f"snapshot_captured_at: {snapshot['captured_at']}")
print()
print("## Summary")
print(f"- line_count: {content['line_count']}")
print(f"- unique_line_count: {content['unique_line_count']}")
print(f"- word_count: {content['word_count']}")
print(f"- link_count: {content['link_count']}")
print()
print("## Excerpt")
for line in content["excerpt_lines"]:
    print(f"- {line}")
if not content["excerpt_lines"]:
    print("- (sin lineas visibles)")
print()
print("## Text")
for line in content["text_lines"]:
    print(f"- {line}")
if not content["text_lines"]:
    print("- (sin lineas visibles)")
print()
print("## Links")
for link in content["links"]:
    text = link["text"] or "(sin texto)"
    url = link["url"] or "(sin url)"
    print(f"- {text} :: {url}")
if not content["links"]:
    print("- (sin links)")
PY
)"

if [ -n "$save_slug" ]; then
  browser_sidecar_make_outbox
  json_path="$(browser_sidecar_artifact_path "$save_slug" json)"
  md_path="$(browser_sidecar_artifact_path "$save_slug" md)"
  printf '%s\n' "$json_output" >"$json_path"
  printf '%s\n' "$markdown_output" >"$md_path"
  "$VALIDATE_MARKDOWN" "$md_path" >/dev/null
  printf 'EXTRACT_ARTIFACT_JSON %s\n' "$(browser_sidecar_display_repo_path "$json_path")" >&2
  printf 'EXTRACT_ARTIFACT_MD %s\n' "$(browser_sidecar_display_repo_path "$md_path")" >&2
fi

if [ "$format" = "json" ]; then
  printf '%s\n' "$json_output"
else
  printf '%s\n' "$markdown_output"
fi
