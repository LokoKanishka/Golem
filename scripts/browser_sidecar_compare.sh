#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

VALIDATE_MARKDOWN="$GOLEM_BROWSER_SIDECAR_REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/browser_sidecar_compare.sh [--format json|markdown] [--save-slug slug] <target_a> <target_b>

Ejemplos:
  ./scripts/browser_sidecar_compare.sh "Reserved Domains" rfc-editor.org
  ./scripts/browser_sidecar_compare.sh --format json "Reserved Domains" rfc-editor.org
  ./scripts/browser_sidecar_compare.sh --save-slug browser-sidecar-compare "Reserved Domains" rfc-editor.org
USAGE
}

format="markdown"
save_slug=""
target_a=""
target_b=""

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
      if [ -z "$target_a" ]; then
        target_a="$1"
      elif [ -z "$target_b" ]; then
        target_b="$1"
      else
        printf 'ERROR: argumentos extra no esperados: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$target_a" ] || [ -z "$target_b" ]; then
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

tmp_a="$(mktemp)"
tmp_b="$(mktemp)"
cleanup() {
  rm -f "$tmp_a" "$tmp_b"
}
trap cleanup EXIT

"$SCRIPT_DIR/browser_sidecar_extract.sh" --format json "$target_a" >"$tmp_a"
"$SCRIPT_DIR/browser_sidecar_extract.sh" --format json "$target_b" >"$tmp_b"

json_output="$(python3 - <<'PY' "$tmp_a" "$tmp_b"
import difflib
import json
import sys
from datetime import datetime, timezone

path_a, path_b = sys.argv[1:3]
data_a = json.load(open(path_a, encoding="utf-8"))
data_b = json.load(open(path_b, encoding="utf-8"))

lines_a = data_a["content"]["text_lines"]
lines_b = data_b["content"]["text_lines"]
set_a = set(lines_a)
set_b = set(lines_b)

common_lines = [line for line in lines_a if line in set_b]
only_a = [line for line in lines_a if line not in set_b]
only_b = [line for line in lines_b if line not in set_a]

ratio = difflib.SequenceMatcher(
    None,
    data_a["content"]["normalized_text"],
    data_b["content"]["normalized_text"],
).ratio()

conclusion = []
if ratio >= 0.5:
    conclusion.append("Las paginas comparten una porcion textual relevante.")
else:
    conclusion.append("Las paginas difieren de forma visible en su texto normalizado.")
if data_a["content"]["line_count"] > data_b["content"]["line_count"]:
    conclusion.append("Target A tiene mas lineas visibles que target B.")
elif data_a["content"]["line_count"] < data_b["content"]["line_count"]:
    conclusion.append("Target B tiene mas lineas visibles que target A.")
else:
    conclusion.append("Ambos targets tienen la misma cantidad de lineas visibles.")
if common_lines:
    conclusion.append("Hay lineas compartidas suficientes para una comparacion basica util.")
else:
    conclusion.append("No hay lineas compartidas exactas; la comparacion queda basada en diferencias.")

payload = {
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "artifact_kind": "browser-sidecar-compare",
    "target_a": {
        "title": data_a["selection"]["title"],
        "url": data_a["selection"]["url"],
        "match_type": data_a["selection"]["match_type"],
        "index": data_a["selection"]["index"],
        "line_count": data_a["content"]["line_count"],
        "word_count": data_a["content"]["word_count"],
        "excerpt_lines": data_a["content"]["excerpt_lines"],
    },
    "target_b": {
        "title": data_b["selection"]["title"],
        "url": data_b["selection"]["url"],
        "match_type": data_b["selection"]["match_type"],
        "index": data_b["selection"]["index"],
        "line_count": data_b["content"]["line_count"],
        "word_count": data_b["content"]["word_count"],
        "excerpt_lines": data_b["content"]["excerpt_lines"],
    },
    "comparison": {
        "similarity_ratio": round(ratio, 4),
        "common_line_count": len(common_lines),
        "only_in_a_count": len(only_a),
        "only_in_b_count": len(only_b),
        "common_lines": common_lines[:12],
        "only_in_a": only_a[:12],
        "only_in_b": only_b[:12],
    },
    "conclusion": conclusion,
}

print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
)"

markdown_output="$(python3 - <<'PY' "$json_output"
import json
import sys

payload = json.loads(sys.argv[1])
a = payload["target_a"]
b = payload["target_b"]
cmp = payload["comparison"]

print("# Browser Sidecar Compare")
print()
print(f"generated_at: {payload['generated_at']}")
print(f"artifact_kind: {payload['artifact_kind']}")
print(f"target_a: {a['title']} :: {a['url']}")
print(f"target_b: {b['title']} :: {b['url']}")
print()
print("## Summary")
print(f"- similarity_ratio: {cmp['similarity_ratio']}")
print(f"- target_a_line_count: {a['line_count']}")
print(f"- target_b_line_count: {b['line_count']}")
print(f"- common_line_count: {cmp['common_line_count']}")
print(f"- only_in_a_count: {cmp['only_in_a_count']}")
print(f"- only_in_b_count: {cmp['only_in_b_count']}")
print()
print("## Target A Excerpt")
for line in a["excerpt_lines"]:
    print(f"- {line}")
if not a["excerpt_lines"]:
    print("- (sin excerpt)")
print()
print("## Target B Excerpt")
for line in b["excerpt_lines"]:
    print(f"- {line}")
if not b["excerpt_lines"]:
    print("- (sin excerpt)")
print()
print("## Common Lines")
for line in cmp["common_lines"]:
    print(f"- {line}")
if not cmp["common_lines"]:
    print("- (sin lineas comunes exactas)")
print()
print("## Only In A")
for line in cmp["only_in_a"]:
    print(f"- {line}")
if not cmp["only_in_a"]:
    print("- (sin diferencias exclusivas en A)")
print()
print("## Only In B")
for line in cmp["only_in_b"]:
    print(f"- {line}")
if not cmp["only_in_b"]:
    print("- (sin diferencias exclusivas en B)")
print()
print("## Conclusion")
for line in payload["conclusion"]:
    print(f"- {line}")
PY
)"

if [ -n "$save_slug" ]; then
  browser_sidecar_make_outbox
  json_path="$(browser_sidecar_artifact_path "$save_slug" json)"
  md_path="$(browser_sidecar_artifact_path "$save_slug" md)"
  printf '%s\n' "$json_output" >"$json_path"
  printf '%s\n' "$markdown_output" >"$md_path"
  "$VALIDATE_MARKDOWN" "$md_path" >/dev/null
  printf 'COMPARE_ARTIFACT_JSON %s\n' "$(browser_sidecar_display_repo_path "$json_path")" >&2
  printf 'COMPARE_ARTIFACT_MD %s\n' "$(browser_sidecar_display_repo_path "$md_path")" >&2
fi

if [ "$format" = "json" ]; then
  printf '%s\n' "$json_output"
else
  printf '%s\n' "$markdown_output"
fi
