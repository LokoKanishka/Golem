#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_export_worker_handoff.sh <task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

task_path="$TASKS_DIR/${task_id}.json"
[ -f "$task_path" ] || fatal "no existe la tarea: $task_id"
mkdir -p "$HANDOFFS_DIR"

packet_rel="handoffs/${task_id}.packet.json"
handoff_rel="handoffs/${task_id}.md"
ticket_rel="handoffs/${task_id}.codex.md"

task_status="$(
  python3 - "$task_path" <<'PY'
import json, pathlib, sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(task.get("status", ""))
print("1" if isinstance(task.get("handoff"), dict) else "0")
PY
)"
status_line="$(printf '%s\n' "$task_status" | sed -n '1p')"
has_handoff="$(printf '%s\n' "$task_status" | sed -n '2p')"

if [ "$has_handoff" != "1" ]; then
  fatal "la tarea $task_id no tiene bloque handoff"
fi

if [ ! -f "$REPO_ROOT/$handoff_rel" ]; then
  [ "$status_line" = "delegated" ] || fatal "no existe handoff markdown y la tarea ya no esta delegated"
  TASK_SKIP_HANDOFF_PACKET_EXPORT=1 ./scripts/task_prepare_codex_handoff.sh "$task_id" >/dev/null
fi

if [ ! -f "$REPO_ROOT/$ticket_rel" ]; then
  [ "$status_line" = "delegated" ] || fatal "no existe codex ticket y la tarea ya no esta delegated"
  TASK_SKIP_HANDOFF_PACKET_EXPORT=1 ./scripts/task_prepare_codex_ticket.sh "$task_id" >/dev/null
fi

tmp_path="$(mktemp "$HANDOFFS_DIR/.handoff-packet-json.XXXXXX.json")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$TASKS_DIR" "$REPO_ROOT" "$packet_rel" "$handoff_rel" "$ticket_rel" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys


def dedupe(items):
    seen = set()
    ordered = []
    for item in items:
        value = str(item or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


task_path = pathlib.Path(sys.argv[1])
tasks_dir = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3]).resolve()
packet_rel, handoff_rel, ticket_rel = sys.argv[4:7]

task = json.loads(task_path.read_text(encoding="utf-8"))
task_id = task.get("task_id", task_path.stem)
handoff = task.get("handoff")
if not isinstance(handoff, dict):
    raise SystemExit(f"ERROR: la tarea {task_id} no tiene bloque handoff")

root_task_id = ""
await_worker_result = False
critical = bool(task.get("critical", False))
await_group_name = ""
await_group_child_ids = []
await_group_step_names = []
downstream_join_groups = []
continuation_policy = {
    "await_worker_result": False,
    "continue_on_failed": False,
    "continue_on_blocked": False,
    "resume_via": "",
    "settle_via": f"./scripts/task_chain_settle.sh {task_id}",
    "degradation_mode": "none",
    "resume_when_all_resolved": False,
    "await_group_name": "",
    "await_group_child_ids": [],
    "await_group_step_names": [],
    "downstream_join_groups": [],
}

parent_task_id = str(task.get("parent_task_id", "")).strip()
if parent_task_id:
    parent_task_path = tasks_dir / f"{parent_task_id}.json"
    if parent_task_path.exists():
        parent = json.loads(parent_task_path.read_text(encoding="utf-8"))
        if parent.get("type") == "task-chain":
            root_task_id = parent_task_id
            steps = ((parent.get("chain_plan") or {}).get("steps") or [])
            for candidate in steps:
                if not candidate.get("await_worker_result"):
                    continue
                await_group_step_names.append(candidate.get("step_name", ""))
                candidate_child_id = str(candidate.get("child_task_id", "")).strip()
                if candidate_child_id:
                    await_group_child_ids.append(candidate_child_id)
            for step in steps:
                if step.get("child_task_id") == task_id or step.get("step_name") == task.get("step_name"):
                    await_worker_result = bool(step.get("await_worker_result", False))
                    critical = bool(step.get("critical", critical))
                    await_group_name = str(step.get("await_group", "")).strip()
                    break
            dependency_groups = ((parent.get("chain_plan") or {}).get("dependency_groups") or [])
            for group in dependency_groups:
                group_name = str(group.get("group_name", "")).strip()
                if not group_name:
                    continue
                if task.get("step_name") in (group.get("step_names") or []):
                    downstream_join_groups.append(group_name)
            continuation_policy.update(
                {
                    "await_worker_result": await_worker_result,
                    "resume_via": f"./scripts/task_chain_resume.sh {root_task_id}" if await_worker_result else "",
                    "degradation_mode": "fail_root_if_critical" if critical else "completed_with_warnings",
                    "resume_when_all_resolved": len(await_group_step_names) > 1,
                    "await_group_name": await_group_name,
                    "await_group_child_ids": dedupe(await_group_child_ids),
                    "await_group_step_names": dedupe(await_group_step_names),
                    "downstream_join_groups": dedupe(downstream_join_groups),
                }
            )

artifact_paths = dedupe(
    [handoff_rel, ticket_rel, packet_rel]
    + [artifact.get("path", "") for artifact in task.get("artifacts", [])]
)

packet = {
    "packet_kind": "worker_handoff_packet",
    "packet_version": "1.0",
    "generated_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
    "child_task_id": task_id,
    "root_task_id": root_task_id,
    "origin": task.get("origin", ""),
    "requested_by": task.get("requested_by", ""),
    "worker_target": handoff.get("delegated_to", "worker_future"),
    "worker_type": task.get("type", ""),
    "objective": task.get("objective", ""),
    "repo_path": repo_root.as_posix(),
    "working_dir": task.get("working_dir", "") or repo_root.as_posix(),
    "canonical_session": task.get("canonical_session", ""),
    "output_mode": task.get("output_mode", "") or "markdown_artifact",
    "outbox_dir": task.get("outbox_dir", "") or f"{repo_root.as_posix()}/outbox/manual",
    "notify_policy": task.get("notify_policy", "") or "manual",
    "await_worker_result": await_worker_result,
    "critical": critical,
    "await_group": {
        "name": await_group_name,
        "step_names": dedupe(await_group_step_names),
        "child_task_ids": dedupe(await_group_child_ids),
        "step_count": len(dedupe(await_group_step_names)),
        "resume_when_all_resolved": len(dedupe(await_group_step_names)) > 1,
    },
    "downstream_join_groups": dedupe(downstream_join_groups),
    "continuation_policy": continuation_policy,
    "artifact_paths": artifact_paths,
    "notes": task.get("notes", []),
    "handoff": {
        "delegated_to": handoff.get("delegated_to", ""),
        "delegated_at": handoff.get("delegated_at", ""),
        "recommended_next_step": handoff.get("recommended_next_step", ""),
        "rationale": handoff.get("rationale", ""),
        "policy_version": handoff.get("policy_version", ""),
        "source_status": handoff.get("source_status", ""),
    },
    "references": {
        "task_path": task_path.relative_to(repo_root).as_posix(),
        "handoff_markdown_path": handoff_rel,
        "codex_ticket_path": ticket_rel,
        "handoff_packet_path": packet_rel,
    },
}

print(json.dumps(packet, indent=2, ensure_ascii=True))
PY

mv "$tmp_path" "$REPO_ROOT/$packet_rel"
trap - EXIT

python3 - "$task_path" "$packet_rel" "$handoff_rel" "$ticket_rel" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
packet_rel, handoff_rel, ticket_rel = sys.argv[2:5]

task = json.loads(task_path.read_text(encoding="utf-8"))
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

artifacts = task.setdefault("artifacts", [])
artifact_keys = {(artifact.get("kind", ""), artifact.get("path", "")) for artifact in artifacts}
for kind, path in [
    ("worker-handoff-markdown", handoff_rel),
    ("worker-codex-ticket", ticket_rel),
    ("worker-handoff-packet", packet_rel),
]:
    if (kind, path) not in artifact_keys:
        artifacts.append({"path": path, "kind": kind, "created_at": now})

outputs = task.setdefault("outputs", [])
already_logged = any(
    output.get("kind") == "worker-handoff-packet" and output.get("packet_path") == packet_rel
    for output in outputs
)
if not already_logged:
    outputs.append(
        {
            "kind": "worker-handoff-packet",
            "captured_at": now,
            "exit_code": 0,
            "content": f"worker handoff packet exported at {packet_rel}",
            "packet_path": packet_rel,
            "handoff_markdown_path": handoff_rel,
            "codex_ticket_path": ticket_rel,
        }
    )

task["updated_at"] = now
task_path.write_text(json.dumps(task, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

printf 'WORKER_HANDOFF_PACKET_OK %s\n' "$packet_rel"
