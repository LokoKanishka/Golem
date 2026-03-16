#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_persist_effective_plan.sh <root_task_id|task_json_path>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

input_ref="${1:-}"
if [ -z "$input_ref" ]; then
  usage
  fatal "falta root_task_id o path"
fi

if [ -f "$input_ref" ]; then
  root_task_path="$input_ref"
elif [ -f "$REPO_ROOT/$input_ref" ]; then
  root_task_path="$REPO_ROOT/$input_ref"
elif [ -f "$TASKS_DIR/${input_ref}.json" ]; then
  root_task_path="$TASKS_DIR/${input_ref}.json"
else
  fatal "no existe la root task-chain: $input_ref"
fi

root_task_path="$(cd "$(dirname "$root_task_path")" && pwd)/$(basename "$root_task_path")"
root_task_id="$(basename "$root_task_path" .json)"
[ -f "$root_task_path" ] || fatal "no existe la root task-chain: $root_task_id"

mkdir -p "$OUTBOX_DIR"

validation_output=""
set +e
validation_output="$(cd "$REPO_ROOT" && ./scripts/validate_chain_plan.sh "$root_task_path" 2>&1)"
validation_exit="$?"
set -e
if [ "$validation_exit" -ne 0 ]; then
  printf '%s\n' "$validation_output"
  exit "$validation_exit"
fi

effective_info="$(
python3 - "$REPO_ROOT" "$root_task_path" <<'PY'
import copy
import datetime
import hashlib
import json
import pathlib
import re
import sys


def as_string(value) -> str:
    return str(value if value is not None else "").strip()


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "chain-plan"


repo_root = pathlib.Path(sys.argv[1]).resolve()
task_path = pathlib.Path(sys.argv[2]).resolve()
task = json.loads(task_path.read_text(encoding="utf-8"))
if task.get("type") != "task-chain":
    raise SystemExit("la tarea indicada no es type=task-chain")

chain_plan = task.get("chain_plan")
if not isinstance(chain_plan, dict):
    raise SystemExit("la root task-chain no tiene chain_plan")

root_task_id = as_string(task.get("task_id")) or task_path.stem
chain_type = as_string(task.get("chain_type"))
title = as_string(task.get("title")) or root_task_id
validated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
artifact_rel = "outbox/manual/{ts}-{slug}-effective-chain-plan.json".format(
    ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"),
    slug=slugify(title),
)
artifact_path = repo_root / artifact_rel
artifact_path.parent.mkdir(parents=True, exist_ok=True)

effective_plan = copy.deepcopy(chain_plan)
effective_plan["effective_plan_for_task_id"] = root_task_id
effective_plan["effective_plan_for_chain_type"] = chain_type
effective_plan["effective_plan_source_task_path"] = str(task_path.relative_to(repo_root))
effective_plan["effective_plan_created_at"] = validated_at

artifact_path.write_text(json.dumps(effective_plan, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
sha256 = hashlib.sha256(artifact_path.read_bytes()).hexdigest()

print(f"effective_plan_path={artifact_rel}")
print(f"effective_plan_sha256={sha256}")
print(f"validated_at={validated_at}")
print(f"validated_plan_version={as_string(chain_plan.get('plan_version') or chain_plan.get('version'))}")
PY
)"
eval "$effective_info"

[ -n "${effective_plan_path:-}" ] || fatal "no se pudo persistir effective plan"
[ -f "$REPO_ROOT/$effective_plan_path" ] || fatal "no existe effective plan artifact: $effective_plan_path"

./scripts/validate_chain_plan.sh "$REPO_ROOT/$effective_plan_path" >/dev/null

preflight_output="$(cd "$REPO_ROOT" && ./scripts/task_chain_preflight.sh "$effective_plan_path" --artifact)"
preflight_artifact_path="$(printf '%s\n' "$preflight_output" | awk '/^PREFLIGHT_ARTIFACT / {print $2}' | tail -n 1)"
[ -n "$preflight_artifact_path" ] || fatal "no se pudo extraer PREFLIGHT_ARTIFACT"
[ -f "$REPO_ROOT/$preflight_artifact_path" ] || fatal "no existe preflight artifact: $preflight_artifact_path"

preflight_info="$(
python3 - "$REPO_ROOT" "$preflight_artifact_path" <<'PY'
import datetime
import hashlib
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
artifact_rel = sys.argv[2]
artifact_path = (repo_root / artifact_rel).resolve()

print(f"preflight_sha256={hashlib.sha256(artifact_path.read_bytes()).hexdigest()}")
print(
    "preflighted_at={ts}".format(
        ts=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    )
)
PY
)"
eval "$preflight_info"

tmp_path="$(mktemp "$TASKS_DIR/.task-chain-effective-plan.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$root_task_path" "$effective_plan_path" "$effective_plan_sha256" "$preflight_artifact_path" "$preflight_sha256" "$validated_plan_version" "$validated_at" "$preflighted_at" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

(
    task_path_raw,
    effective_plan_path,
    effective_plan_sha256,
    preflight_artifact_path,
    preflight_sha256,
    validated_plan_version,
    validated_at,
    preflighted_at,
) = sys.argv[1:9]

task_path = pathlib.Path(task_path_raw)
task = json.loads(task_path.read_text(encoding="utf-8"))
effective_plan = json.loads((task_path.parent.parent / effective_plan_path).read_text(encoding="utf-8"))
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

task["effective_chain_plan"] = effective_plan
task["effective_plan_path"] = effective_plan_path
task["effective_plan_sha256"] = effective_plan_sha256
task["preflight_artifact_path"] = preflight_artifact_path
task["preflight_sha256"] = preflight_sha256
task["validated_plan_version"] = validated_plan_version
task["validated_at"] = validated_at
task["preflighted_at"] = preflighted_at

artifacts = task.setdefault("artifacts", [])
artifact_keys = {(artifact.get("kind", ""), artifact.get("path", "")) for artifact in artifacts if isinstance(artifact, dict)}
for kind, path, sha256 in (
    ("effective-chain-plan", effective_plan_path, effective_plan_sha256),
    ("chain-plan-preflight", preflight_artifact_path, preflight_sha256),
):
    if (kind, path) in artifact_keys:
        continue
    artifacts.append(
        {
            "path": path,
            "kind": kind,
            "created_at": preflighted_at,
            "sha256": sha256,
            "plan_version": validated_plan_version,
        }
    )
    artifact_keys.add((kind, path))

outputs = task.setdefault("outputs", [])
traceability_key = (effective_plan_path, preflight_artifact_path)
existing_output = False
for output in outputs:
    if not isinstance(output, dict):
        continue
    if output.get("kind") != "chain-plan-traceability":
        continue
    if (output.get("effective_plan_path", ""), output.get("preflight_artifact_path", "")) == traceability_key:
        existing_output = True
        break

if not existing_output:
    outputs.append(
        {
            "kind": "chain-plan-traceability",
            "captured_at": preflighted_at,
            "exit_code": 0,
            "content": "persisted effective chain plan and preflight artifacts for this root",
            "effective_plan_path": effective_plan_path,
            "effective_plan_sha256": effective_plan_sha256,
            "preflight_artifact_path": preflight_artifact_path,
            "preflight_sha256": preflight_sha256,
            "plan_version": validated_plan_version,
        }
    )

note = f"effective chain plan persisted at {validated_at} and preflight artifact frozen at {preflighted_at}"
notes = task.setdefault("notes", [])
if note not in notes:
    notes.append(note)

task["updated_at"] = now
json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$root_task_path"
trap - EXIT

printf 'CHAIN_EFFECTIVE_PLAN_PERSISTED %s\n' "$root_task_id"
printf 'effective_plan_path: %s\n' "$effective_plan_path"
printf 'effective_plan_sha256: %s\n' "$effective_plan_sha256"
printf 'preflight_artifact_path: %s\n' "$preflight_artifact_path"
printf 'preflight_sha256: %s\n' "$preflight_sha256"
printf 'validated_plan_version: %s\n' "$validated_plan_version"
printf 'validated_at: %s\n' "$validated_at"
printf 'preflighted_at: %s\n' "$preflighted_at"
