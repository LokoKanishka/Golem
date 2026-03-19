#!/usr/bin/env bash
set -euo pipefail

output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      printf 'ERROR: argumento no soportado: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift || true
done

target=""
source_kind=""
note=""

if [ -n "${GOLEM_WHATSAPP_CANARY_TARGET:-}" ]; then
  target="${GOLEM_WHATSAPP_CANARY_TARGET}"
  source_kind="env"
  note="resolved from GOLEM_WHATSAPP_CANARY_TARGET"
else
  set +e
  status_output="$(openclaw channels status 2>&1)"
  status_exit="$?"
  set -e
  if [ "$status_exit" -eq 0 ]; then
    target="$(printf '%s\n' "$status_output" | sed -n 's/.*allow:\([+0-9][+0-9]*\).*/\1/p' | head -n 1)"
    if [ -n "$target" ]; then
      source_kind="runtime-allowlist"
      note="resolved from openclaw channels status allowlist"
    fi
  fi
fi

if [ "$output_json" = "1" ]; then
  python3 - "$target" "$source_kind" "$note" <<'PY'
import json
import sys

target, source_kind, note = sys.argv[1:4]
print(json.dumps({
    "target": target,
    "source": source_kind,
    "note": note,
    "resolved": bool(target),
}, ensure_ascii=True))
PY
  exit 0
fi

if [ -n "$target" ]; then
  printf '%s\n' "$target"
  exit 0
fi

exit 2
