#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_import_worker_result.sh <packet_path> [--settle]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

packet_arg="${1:-}"
if [ -z "$packet_arg" ]; then
  usage
  fatal "falta packet_path"
fi
shift

settle_after="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --settle)
      settle_after="true"
      shift
      ;;
    *)
      fatal "argumento no reconocido: $1"
      ;;
  esac
done

packet_path="$(
  python3 - "$REPO_ROOT" "$packet_arg" <<'PY'
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
packet_arg = pathlib.Path(sys.argv[2])
if not packet_arg.is_absolute():
    packet_path = (repo_root / packet_arg).resolve()
else:
    packet_path = packet_arg.resolve()
print(packet_path)
PY
)"

[ -f "$packet_path" ] || fatal "no existe el packet: $packet_arg"

eval "$(
  python3 - "$REPO_ROOT" "$packet_path" "$TASKS_DIR" <<'PY'
import datetime
import hashlib
import json
import pathlib
import shlex
import sys


def fail(message: str) -> None:
    print(f"ERROR={shlex.quote(message)}")
    raise SystemExit(0)


def to_repo_rel(path: pathlib.Path, repo_root: pathlib.Path) -> str:
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        fail(f"el packet debe vivir dentro del repo: {path}")


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


repo_root = pathlib.Path(sys.argv[1]).resolve()
packet_path = pathlib.Path(sys.argv[2]).resolve()
tasks_dir = pathlib.Path(sys.argv[3]).resolve()

packet_raw = packet_path.read_text(encoding="utf-8")
try:
    packet = json.loads(packet_raw)
except json.JSONDecodeError as exc:
    fail(f"packet JSON invalido: {exc}")

if not isinstance(packet, dict):
    fail("el packet debe ser un objeto JSON")

if packet.get("packet_kind") != "worker_result_packet":
    fail("packet_kind invalido; usar worker_result_packet")

if packet.get("packet_version") != "1.0":
    fail("packet_version no soportada; usar 1.0")

generated_at = str(packet.get("generated_at", "")).strip()
if not generated_at:
    fail("generated_at es obligatorio")
try:
    datetime.datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
except ValueError:
    fail("generated_at debe ser timestamp ISO 8601 valido")

child_task_id = str(packet.get("child_task_id", "")).strip()
if not child_task_id:
    fail("child_task_id es obligatorio")

result_status = str(packet.get("result_status", "")).strip()
if result_status not in {"done", "failed", "blocked"}:
    fail("result_status invalido; usar done, failed o blocked")

summary = " ".join(str(packet.get("summary", "")).split())
if not summary:
    fail("summary es obligatorio")

worker_name = str(packet.get("worker_name", "")).strip()
source = str(packet.get("source", "")).strip()
if not worker_name and not source:
    fail("worker_name o source son obligatorios")

notes = packet.get("notes", [])
if notes and not isinstance(notes, list):
    fail("notes debe ser una lista")

artifact_paths = packet.get("artifact_paths", [])
if artifact_paths and not isinstance(artifact_paths, list):
    fail("artifact_paths debe ser una lista")

commit_info = packet.get("commit_info", {})
if commit_info and not isinstance(commit_info, dict):
    fail("commit_info debe ser un objeto")

evidence = packet.get("evidence", {})
if evidence and not isinstance(evidence, dict):
    fail("evidence debe ser un objeto")

child_task_path = tasks_dir / f"{child_task_id}.json"
if not child_task_path.exists():
    fail(f"no existe la child task: {child_task_id}")

child_task = json.loads(child_task_path.read_text(encoding="utf-8"))
child_status = str(child_task.get("status", "")).strip()
if child_status not in {"delegated", "worker_running"}:
    fail(f"la child task {child_task_id} no esta importable desde status={child_status}")

if not isinstance(child_task.get("handoff"), dict):
    fail(f"la child task {child_task_id} no tiene handoff")

existing_result = latest_worker_result_output(child_task)
if existing_result:
    fail(f"la child task {child_task_id} ya tiene worker-result registrado")

root_task_id = str(packet.get("root_task_id", "")).strip()
real_root_task_id = str(child_task.get("parent_task_id", "")).strip()
if root_task_id and real_root_task_id and root_task_id != real_root_task_id:
    fail(f"root_task_id inconsistente: packet={root_task_id} task={real_root_task_id}")
if not root_task_id:
    root_task_id = real_root_task_id

if root_task_id:
    root_task_path = tasks_dir / f"{root_task_id}.json"
    if not root_task_path.exists():
        fail(f"root_task_id no existe: {root_task_id}")
    root_task = json.loads(root_task_path.read_text(encoding="utf-8"))
    if root_task.get("type") != "task-chain":
        fail(f"root_task_id no apunta a task-chain: {root_task_id}")

artifact_args = []
artifact_rel_paths = []
for raw in artifact_paths:
    path = pathlib.Path(str(raw))
    if not path.is_absolute():
      resolved = (repo_root / path).resolve()
    else:
      resolved = path.resolve()
    try:
        rel_path = resolved.relative_to(repo_root).as_posix()
    except ValueError:
        fail(f"artifact fuera del repo: {raw}")
    if not resolved.exists():
        fail(f"artifact inexistente: {raw}")
    artifact_args.extend(["--artifact", rel_path])
    artifact_rel_paths.append(rel_path)

packet_rel = to_repo_rel(packet_path, repo_root)
packet_sha256 = hashlib.sha256(packet_raw.encode("utf-8")).hexdigest()

extra_payload = {
    "packet_kind": packet.get("packet_kind"),
    "packet_version": packet.get("packet_version"),
    "packet_path": packet_rel,
    "packet_sha256": packet_sha256,
    "generated_at": generated_at,
    "imported_via": "task_import_worker_result",
    "source": source or worker_name,
    "worker_name": worker_name or source,
    "root_task_id": root_task_id,
    "packet_notes": notes or [],
    "commit_info": commit_info or {},
    "evidence": evidence or {},
}

values = {
    "ERROR": "",
    "CHILD_TASK_ID": child_task_id,
    "ROOT_TASK_ID": root_task_id,
    "RESULT_STATUS": result_status,
    "SUMMARY": summary,
    "PACKET_REL": packet_rel,
    "PACKET_SHA256": packet_sha256,
    "PACKET_GENERATED_AT": generated_at,
    "ARTIFACT_ARGS_JSON": json.dumps(artifact_args),
    "EXTRA_JSON": json.dumps(extra_payload),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

[ -z "${ERROR:-}" ] || fatal "$ERROR"

record_args=("$CHILD_TASK_ID" "$RESULT_STATUS" "$SUMMARY")
while IFS= read -r item; do
  [ -n "$item" ] || continue
  record_args+=("$item")
done < <(
  python3 - "$ARTIFACT_ARGS_JSON" <<'PY'
import json
import sys
for value in json.loads(sys.argv[1]):
    print(value)
PY
)

WORKER_RESULT_EXTRA_JSON="$EXTRA_JSON" ./scripts/task_record_worker_result.sh "${record_args[@]}"
./scripts/task_add_artifact.sh "$CHILD_TASK_ID" "worker-result-packet" "$PACKET_REL" >/dev/null

python3 - "$TASKS_DIR/${CHILD_TASK_ID}.json" "$PACKET_REL" "$PACKET_GENERATED_AT" "$PACKET_SHA256" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
packet_rel = sys.argv[2]
packet_generated_at = sys.argv[3]
packet_sha256 = sys.argv[4]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task.setdefault("notes", []).append(
    f"worker result imported from packet {packet_rel} generated_at={packet_generated_at} sha256={packet_sha256}"
)
task["updated_at"] = now
task_path.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

printf 'TASK_WORKER_RESULT_IMPORTED %s %s\n' "$CHILD_TASK_ID" "$PACKET_REL"

if [ "$settle_after" = "true" ]; then
  ./scripts/task_chain_settle.sh "$CHILD_TASK_ID"
fi
