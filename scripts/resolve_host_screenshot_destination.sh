#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/resolve_host_screenshot_destination.sh <task_id> <target_kind> [output_hint] [--json]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
target_kind="${2:-}"
shift 2 || true

output_hint=""
output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      if [ -n "$output_hint" ]; then
        usage
        fatal "argumento no soportado: $1"
      fi
      output_hint="$1"
      ;;
  esac
  shift
done

if [ -z "$task_id" ] || [ -z "$target_kind" ]; then
  usage
  fatal "faltan task_id o target_kind"
fi

mkdir -p "$OUTBOX_DIR"

resolution_json="$(python3 - "$REPO_ROOT" "$OUTBOX_DIR" "$task_id" "$target_kind" "$output_hint" <<'PY'
import datetime
import json
import pathlib
import re
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
outbox_dir = pathlib.Path(sys.argv[2]).resolve()
task_id, target_kind, output_hint = sys.argv[3:6]

timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
safe_target = re.sub(r"[^A-Za-z0-9._-]+", "-", target_kind.strip().lower()).strip("-") or "screenshot"
default_filename = f"{timestamp}-{task_id}-{safe_target}.png"

requested_path = ""
resolution_reason = ""

if output_hint:
    requested_path = output_hint
    raw_path = pathlib.Path(output_hint).expanduser()
    if raw_path.is_absolute():
        candidate = raw_path
        if raw_path.exists() and raw_path.is_dir():
            candidate = raw_path / default_filename
            resolution_reason = "absolute directory hint reused for screenshot output"
        elif output_hint.endswith(("/", "\\")):
            candidate.mkdir(parents=True, exist_ok=True)
            candidate = candidate / default_filename
            resolution_reason = "absolute directory-like hint materialized for screenshot output"
        elif candidate.suffix == "":
            candidate = candidate.with_suffix(".png")
            resolution_reason = "absolute file hint normalized to png"
        else:
            resolution_reason = "absolute file hint accepted as screenshot destination"
    else:
        if "/" in output_hint or output_hint.startswith("."):
            candidate = (repo_root / raw_path).resolve(strict=False)
            if output_hint.endswith(("/", "\\")):
                candidate.mkdir(parents=True, exist_ok=True)
                candidate = candidate / default_filename
                resolution_reason = "relative directory hint resolved inside repo for screenshot output"
            elif candidate.suffix == "":
                candidate = candidate.with_suffix(".png")
                resolution_reason = "relative file hint normalized to png inside repo"
            else:
                resolution_reason = "relative file hint resolved inside repo for screenshot output"
        else:
            candidate = outbox_dir / output_hint
            if candidate.suffix == "":
                candidate = candidate.with_suffix(".png")
            resolution_reason = "bare filename hint resolved inside outbox/manual"
else:
    candidate = outbox_dir / default_filename
    resolution_reason = "default host screenshot staging path in outbox/manual"

candidate.parent.mkdir(parents=True, exist_ok=True)
normalized = str(candidate.resolve(strict=False))

payload = {
    "task_id": task_id,
    "target_kind": target_kind,
    "output_hint": output_hint,
    "requested_path": requested_path,
    "resolved_path": str(candidate),
    "absolute_path": normalized,
    "normalized_path": normalized,
    "filename": candidate.name,
    "directory": str(candidate.parent),
    "resolution_reason": resolution_reason,
}

print(json.dumps(payload, ensure_ascii=True))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$resolution_json"
else
  python3 - "$resolution_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(f"task_id: {payload.get('task_id', '')}")
print(f"target_kind: {payload.get('target_kind', '')}")
print(f"requested_path: {payload.get('requested_path', '') or '(none)'}")
print(f"resolved_path: {payload.get('resolved_path', '')}")
print(f"normalized_path: {payload.get('normalized_path', '')}")
print(f"resolution_reason: {payload.get('resolution_reason', '')}")
PY
fi
