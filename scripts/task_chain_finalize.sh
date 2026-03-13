#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_finalize.sh <root_task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta root_task_id"
fi

root_task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$root_task_path" ]; then
  fatal "no existe la tarea raiz: $task_id"
fi

mkdir -p "$OUTBOX_DIR"

summary_json="$(
  python3 - "$TASKS_DIR" "$root_task_path" <<'PY'
import datetime
import json
import pathlib
import re
import sys

tasks_dir = pathlib.Path(sys.argv[1])
root_task_path = pathlib.Path(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    root_task = json.load(fh)

root_task_id = root_task.get("task_id", root_task_path.stem)
chain_type = root_task.get("chain_type", "")
if not chain_type:
    print("ERROR: la tarea raiz no tiene chain_type", file=sys.stderr)
    raise SystemExit(1)

children = []
for path in sorted(tasks_dir.glob("*.json")):
    if not path.is_file():
        continue
    with path.open(encoding="utf-8") as fh:
        task = json.load(fh)
    if (task.get("parent_task_id") or "") == root_task_id:
        children.append(task)

child_task_ids = [task.get("task_id", "") for task in children]
children_done = 0
children_failed = 0
children_with_warnings = 0
aggregated_artifacts = []
failed_child_ids = []
warning_child_ids = []

for child in children:
    status = child.get("status", "")
    child_has_warning = False

    if status == "done":
        children_done += 1
    elif status in {"failed", "cancelled"}:
        children_failed += 1
        failed_child_ids.append(child.get("task_id", ""))

    for output in child.get("outputs", []):
        state_markers = [
            str(output.get("estado_general", "")).upper(),
            str(output.get("status", "")).upper(),
        ]
        if "WARN" in state_markers or "WARNING" in state_markers:
            child_has_warning = True

    if child_has_warning:
        children_with_warnings += 1
        warning_child_ids.append(child.get("task_id", ""))

    for artifact in child.get("artifacts", []):
        path = artifact.get("path", "")
        if path:
            aggregated_artifacts.append(path)

if children_failed > 0:
    chain_status = "failed"
    final_task_status = "failed"
elif children_with_warnings > 0:
    chain_status = "completed_with_warnings"
    final_task_status = "done"
else:
    chain_status = "completed"
    final_task_status = "done"

generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
slug_base = re.sub(r"[^a-z0-9]+", "-", chain_type.lower()).strip("-") or "chain"
artifact_rel = "outbox/manual/{ts}-{slug}-summary.md".format(
    ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
    slug=slug_base,
)

summary = {
    "root_task_id": root_task_id,
    "chain_type": chain_type,
    "generated_at": generated_at,
    "child_task_ids": child_task_ids,
    "child_count": len(children),
    "children_done": children_done,
    "children_failed": children_failed,
    "children_with_warnings": children_with_warnings,
    "artifact_paths": aggregated_artifacts,
    "failed_child_ids": failed_child_ids,
    "warning_child_ids": warning_child_ids,
    "chain_status": chain_status,
    "final_task_status": final_task_status,
}

print(json.dumps(summary))
PY
)"

artifact_rel="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(summary["artifact_rel"] if "artifact_rel" in summary else "")
PY
)"

if [ -z "$artifact_rel" ]; then
  artifact_rel="$(
    python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
import datetime
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
slug = summary["chain_type"].lower().replace("_", "-")
print(f"outbox/manual/{ts}-{slug}-summary.md")
PY
  )"
fi

artifact_abs="$REPO_ROOT/$artifact_rel"
tmp_artifact="$(mktemp "$OUTBOX_DIR/.chain-summary.XXXXXX.md")"
trap 'rm -f "$tmp_artifact"' EXIT

python3 - "$root_task_path" "$summary_json" >"$tmp_artifact" <<'PY'
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    root_task = json.load(fh)

print(f"# Chain Summary: {summary['chain_type']}")
print()
print(f"generated_at: {summary['generated_at']}")
print(f"repo: {root_task_path.parent.parent.as_posix()}")
print("task_type: task-chain")
print(f"root_task_id: {summary['root_task_id']}")
print(f"chain_type: {summary['chain_type']}")
print()
print("## Summary")
print(f"- final_task_status: {summary['final_task_status']}")
print(f"- chain_status: {summary['chain_status']}")
print(f"- child_count: {summary['child_count']}")
print(f"- children_done: {summary['children_done']}")
print(f"- children_failed: {summary['children_failed']}")
print(f"- children_with_warnings: {summary['children_with_warnings']}")
print()
print("## Child Tasks")
if not summary["child_task_ids"]:
    print("- (none)")
else:
    for child_id in summary["child_task_ids"]:
        print(f"- {child_id}")
print()
print("## Result")
if summary["chain_status"] == "failed":
    print("- Chain closed as failed because at least one critical child failed.")
elif summary["chain_status"] == "completed_with_warnings":
    print("- Chain closed as done with warnings because child tasks completed but warning-level signals were detected.")
else:
    print("- Chain completed without child failures or warning-level signals.")
print()
print("## Aggregated Artifacts")
if not summary["artifact_paths"]:
    print("- (none)")
else:
    for path in summary["artifact_paths"]:
        print(f"- {path}")
print()
print("## Notes")
if summary["failed_child_ids"]:
    print(f"- failed_child_ids: {', '.join(summary['failed_child_ids'])}")
if summary["warning_child_ids"]:
    print(f"- warning_child_ids: {', '.join(summary['warning_child_ids'])}")
if not summary["failed_child_ids"] and not summary["warning_child_ids"]:
    print("- no extra failure or warning notes")
PY

"$VALIDATE_MARKDOWN" "$tmp_artifact" >/dev/null
mv "$tmp_artifact" "$artifact_abs"
trap - EXIT
chmod 664 "$artifact_abs"

tmp_task="$(mktemp "$TASKS_DIR/.task-chain-finalize.XXXXXX.tmp")"
trap 'rm -f "$tmp_task"' EXIT
python3 - "$root_task_path" "$summary_json" >"$tmp_task" <<'PY'
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["chain_status"] = summary["chain_status"]
task["chain_summary"] = {
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
}

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$root_task_path"
trap - EXIT

summary_content="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(
    "chain_status={chain_status} child_count={child_count} children_done={children_done} "
    "children_failed={children_failed} children_with_warnings={children_with_warnings}".format(
        chain_status=summary["chain_status"],
        child_count=summary["child_count"],
        children_done=summary["children_done"],
        children_failed=summary["children_failed"],
        children_with_warnings=summary["children_with_warnings"],
    )
)
PY
)"

summary_extra_json="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
extra = {
    "chain_type": summary["chain_type"],
    "chain_status": summary["chain_status"],
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
}
print(json.dumps(extra))
PY
)"

TASK_OUTPUT_EXTRA_JSON="$summary_extra_json" ./scripts/task_add_output.sh "$task_id" "chain-summary" 0 "$summary_content"
./scripts/task_add_artifact.sh "$task_id" "chain-summary" "$artifact_rel"

close_status="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(summary["final_task_status"])
PY
)"

close_note="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
if summary["chain_status"] == "failed":
    print("chain finalized with failed critical child")
elif summary["chain_status"] == "completed_with_warnings":
    print("chain finalized with warnings recorded in child tasks")
else:
    print("chain finalized successfully")
PY
)"

./scripts/task_close.sh "$task_id" "$close_status" "$close_note"
printf 'TASK_CHAIN_FINALIZED %s %s\n' "$task_id" "$artifact_rel"
