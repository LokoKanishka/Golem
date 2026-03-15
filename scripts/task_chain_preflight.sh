#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_preflight.sh <task_id|task_json_path|plan_json_path> [--artifact]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

input_ref=""
write_artifact="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --artifact)
      write_artifact="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -n "$input_ref" ]; then
        usage
        fatal "solo se acepta un input"
      fi
      input_ref="$1"
      shift
      ;;
  esac
done

if [ -z "$input_ref" ]; then
  usage
  fatal "falta task_id o path"
fi

validation_output=""
set +e
validation_output="$(cd "$REPO_ROOT" && ./scripts/validate_chain_plan.sh "$input_ref" 2>&1)"
validation_exit="$?"
set -e
if [ "$validation_exit" -ne 0 ]; then
  printf '%s\n' "$validation_output"
  printf 'CHAIN_PLAN_PREFLIGHT_FAIL invalid_chain_plan\n' >&2
  exit "$validation_exit"
fi

mkdir -p "$OUTBOX_DIR"

preflight_output="$(
python3 - "$REPO_ROOT" "$input_ref" "$write_artifact" "$validation_output" <<'PY'
import datetime
import json
import pathlib
import re
import sys


def as_string(value) -> str:
    return str(value if value is not None else "").strip()


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "chain-plan"


def load_source(repo_root: pathlib.Path, raw_ref: str):
    tasks_dir = repo_root / "tasks"
    direct = pathlib.Path(raw_ref)
    candidates = []
    if direct.is_file():
        candidates.append(direct.resolve())
    repo_candidate = (repo_root / raw_ref).resolve()
    if repo_candidate.is_file():
        candidates.append(repo_candidate)
    task_candidate = (tasks_dir / f"{raw_ref}.json").resolve()
    if task_candidate.is_file():
        candidates.append(task_candidate)
    if not candidates:
        raise FileNotFoundError(f"no existe task/plan en: {raw_ref}")

    path = candidates[0]
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("el documento raiz debe ser un objeto JSON")

    root_task_id = as_string(data.get("task_id")) or path.stem
    if isinstance(data.get("chain_plan"), dict):
        root = data
        plan = data["chain_plan"]
        source_kind = "task"
        source_id = root_task_id
    else:
        root = {}
        plan = data
        source_kind = "plan"
        source_id = root_task_id

    return path, source_kind, source_id, root, plan


def unique(values):
    seen = set()
    ordered = []
    for value in values:
        text = as_string(value)
        if not text or text in seen:
            continue
        seen.add(text)
        ordered.append(text)
    return ordered


repo_root = pathlib.Path(sys.argv[1]).resolve()
raw_ref = sys.argv[2]
write_artifact = sys.argv[3] == "true"
validation_output = sys.argv[4]

source_path, source_kind, source_id, root, plan = load_source(repo_root, raw_ref)

plan_kind = as_string(plan.get("plan_kind")) or "chain_plan"
plan_version = as_string(plan.get("plan_version") or plan.get("version"))
steps = plan.get("steps") or []
dependency_groups = plan.get("dependency_groups") or []
steps = sorted(
    [step for step in steps if isinstance(step, dict)],
    key=lambda item: (int(item.get("step_order", 0) or 0), item.get("step_name", "")),
)
step_by_name = {as_string(step.get("step_name")): step for step in steps if as_string(step.get("step_name"))}
awaited_worker_steps = [
    step for step in steps
    if step.get("execution_mode") == "worker" and bool(step.get("await_worker_result", False))
]
awaited_worker_names = [as_string(step.get("step_name")) for step in awaited_worker_steps]
critical_step_names = [as_string(step.get("step_name")) for step in steps if bool(step.get("critical", False))]

group_by_name = {}
for group in dependency_groups:
    if not isinstance(group, dict):
        continue
    group_name = as_string(group.get("group_name") or group.get("name"))
    if not group_name:
        continue
    step_names = unique(group.get("step_names") or [])
    used_by = unique(group.get("used_by_step_names") or [])
    group_by_name[group_name] = {
        "group_name": group_name,
        "group_type": as_string(group.get("group_type") or "join_barrier") or "join_barrier",
        "step_names": step_names,
        "used_by_step_names": used_by,
        "satisfaction_policy": as_string(group.get("satisfaction_policy") or "all_done") or "all_done",
        "continue_on_blocked": bool(group.get("continue_on_blocked", False)),
        "continue_on_failed": bool(group.get("continue_on_failed", False)),
    }

graph_edges = []
for step in steps:
    step_name = as_string(step.get("step_name"))
    for dependency in step.get("depends_on_step_names") or []:
        graph_edges.append(f"{dependency} -> {step_name}")

barrier_lines = []
partial_openers = []
full_join_steps = []
waiting_by_design = []

awaited_worker_set = set(awaited_worker_names)
for group_name, group in group_by_name.items():
    group_steps = group["step_names"]
    used_by = group["used_by_step_names"]
    is_subset_of_awaited = bool(group_steps) and set(group_steps).issubset(awaited_worker_set)
    is_full_await_join = awaited_worker_set and set(group_steps) == awaited_worker_set
    is_partial_barrier = awaited_worker_set and is_subset_of_awaited and set(group_steps) != awaited_worker_set

    if is_partial_barrier:
        barrier_role = "partial_continuation_barrier"
        partial_openers.extend(used_by)
    elif is_full_await_join:
        barrier_role = "full_join_barrier"
        full_join_steps.extend(used_by)
    elif len(group_steps) > 1:
        barrier_role = "multi_dependency_barrier"
    else:
        barrier_role = "explicit_barrier"

    waiting_by_design.extend(used_by)
    barrier_lines.append(
        {
            "group_name": group_name,
            "group_type": group["group_type"],
            "barrier_role": barrier_role,
            "step_names": group_steps,
            "used_by_step_names": used_by,
            "satisfaction_policy": group["satisfaction_policy"],
            "continue_on_blocked": group["continue_on_blocked"],
            "continue_on_failed": group["continue_on_failed"],
        }
    )

partial_openers = unique(partial_openers)
full_join_steps = unique(full_join_steps)
waiting_by_design = unique(waiting_by_design)

blocked_conditions = []
failed_conditions = []
for step in steps:
    step_name = as_string(step.get("step_name"))
    critical = bool(step.get("critical", False))
    execution_mode = as_string(step.get("execution_mode"))
    join_group = as_string(step.get("join_group"))
    condition_source_step = as_string(step.get("condition_source_step"))

    if critical:
        blocked_conditions.append(f"if {step_name} reaches blocked, the root can close blocked")
        failed_conditions.append(f"if {step_name} reaches failed, the root can close failed")
    if execution_mode == "local" and join_group:
        blocked_conditions.append(
            f"{step_name} stays waiting until barrier {join_group} is satisfied; if that barrier blocks, the step is skipped"
        )
        failed_conditions.append(
            f"{step_name} is skipped if barrier {join_group} fails because one dependency failed or was skipped"
        )
    if condition_source_step:
        blocked_conditions.append(
            f"{step_name} only becomes runnable if {condition_source_step} matches its conditional worker_result_status gate"
        )

blocked_conditions = unique(blocked_conditions)
failed_conditions = unique(failed_conditions)

awaiting_lines = []
if awaited_worker_names:
    awaiting_lines.append(
        "root enters awaiting_worker_result after delegation while any awaited worker result is still unresolved: "
        + ", ".join(awaited_worker_names)
    )
    awaiting_lines.append(
        "root leaves awaiting_worker_result only after every awaited worker is terminal or a critical worker already forced blocked/failed closure"
    )

step_lines = []
for step in steps:
    step_name = as_string(step.get("step_name"))
    execution_mode = as_string(step.get("execution_mode"))
    critical = "yes" if step.get("critical") else "no"
    awaited = "yes" if step.get("await_worker_result") else "no"
    depends = unique(step.get("depends_on_step_names") or [])
    join_group = as_string(step.get("join_group")) or "(none)"
    await_group = as_string(step.get("await_group")) or "(none)"
    conditional = ""
    if as_string(step.get("condition_source_step")):
        conditional = (
            f" | conditional_on={as_string(step.get('condition_source_step'))}"
            f" -> {as_string(step.get('run_if_worker_result_status')) or '(none)'}"
        )
    step_lines.append(
        f"- [{step.get('step_order')}] {step_name} | kind={execution_mode} | critical={critical} "
        f"| await_worker_result={awaited} | depends_on={', '.join(depends) if depends else '(none)'} "
        f"| join_group={join_group} | await_group={await_group}{conditional}"
    )

dag_lines = []
for step in steps:
    step_name = as_string(step.get("step_name"))
    depends = unique(step.get("depends_on_step_names") or [])
    if depends:
        dag_lines.append(f"- {step_name} <= {', '.join(depends)}")
    else:
        dag_lines.append(f"- {step_name} <= (root entry)")

for barrier in barrier_lines:
    dag_lines.append(
        f"- barrier {barrier['group_name']} <= {', '.join(barrier['step_names']) or '(none)'} -> "
        f"{', '.join(barrier['used_by_step_names']) or '(none)'}"
    )

title = as_string(root.get("title")) or source_id or source_path.stem
artifact_rel = ""
generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

lines = []
lines.append(f"CHAIN_PLAN_PREFLIGHT_OK {source_path}")
lines.append(f"source_kind: {source_kind}")
lines.append(f"source_id: {source_id}")
lines.append(f"plan_kind: {plan_kind}")
lines.append(f"plan_version: {plan_version}")
lines.append(f"title: {title}")
lines.append(f"step_count: {len(steps)}")
lines.append(f"local_step_count: {sum(1 for step in steps if as_string(step.get('execution_mode')) == 'local')}")
lines.append(f"worker_step_count: {sum(1 for step in steps if as_string(step.get('execution_mode')) == 'worker')}")
lines.append(f"await_worker_result_step_count: {len(awaited_worker_steps)}")
lines.append(f"dependency_group_count: {len(barrier_lines)}")
lines.append("")
lines.append("## Validation Base")
for row in validation_output.splitlines():
    lines.append(row)
lines.append("")
lines.append("## Steps")
lines.extend(step_lines or ["- (none)"])
lines.append("")
lines.append("## DAG")
lines.extend(dag_lines or ["- (none)"])
lines.append("")
lines.append("## Barriers")
if not barrier_lines:
    lines.append("- (none)")
else:
    for barrier in barrier_lines:
        lines.append(
            f"- {barrier['group_name']} | type={barrier['group_type']} | role={barrier['barrier_role']} | "
            f"steps={', '.join(barrier['step_names']) or '(none)'} | "
            f"used_by={', '.join(barrier['used_by_step_names']) or '(none)'}"
        )
lines.append("")
lines.append("## Continuation Semantics")
lines.append(
    f"- partial_continuation_steps: {', '.join(partial_openers) if partial_openers else '(none)'}"
)
lines.append(
    f"- full_join_steps: {', '.join(full_join_steps) if full_join_steps else '(none)'}"
)
lines.append(
    f"- waiting_by_design_until_barriers_resolve: {', '.join(waiting_by_design) if waiting_by_design else '(none)'}"
)
lines.append("")
lines.append("## Root State Semantics")
lines.append(
    f"- awaited_worker_steps: {', '.join(awaited_worker_names) if awaited_worker_names else '(none)'}"
)
if awaiting_lines:
    lines.extend(f"- {row}" for row in awaiting_lines)
else:
    lines.append("- root does not enter awaiting_worker_result because the plan has no awaited worker steps")
lines.extend(f"- {row}" for row in blocked_conditions)
lines.extend(f"- {row}" for row in failed_conditions)

output_text = "\n".join(lines)
print(output_text)

if write_artifact:
    artifact_rel = "outbox/manual/{ts}-{slug}-chain-plan-preflight.md".format(
        ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        slug=slugify(title),
    )
    artifact_path = repo_root / artifact_rel
    artifact_path.parent.mkdir(parents=True, exist_ok=True)

    md_lines = [
        "# Chain Plan Preflight",
        "",
        f"generated_at: {generated_at}",
        f"repo: {repo_root.as_posix()}",
        "task_type: chain-plan-preflight",
        f"source_kind: {source_kind}",
        f"source_id: {source_id}",
        f"plan_kind: {plan_kind}",
        f"plan_version: {plan_version}",
        f"preflight_artifact_path: {artifact_rel}",
        "",
        "## Summary",
        f"- title: {title}",
        f"- step_count: {len(steps)}",
        f"- local_step_count: {sum(1 for step in steps if as_string(step.get('execution_mode')) == 'local')}",
        f"- worker_step_count: {sum(1 for step in steps if as_string(step.get('execution_mode')) == 'worker')}",
        f"- await_worker_result_step_count: {len(awaited_worker_steps)}",
        f"- dependency_group_count: {len(barrier_lines)}",
        f"- partial_continuation_steps: {', '.join(partial_openers) if partial_openers else '(none)'}",
        f"- full_join_steps: {', '.join(full_join_steps) if full_join_steps else '(none)'}",
        "",
        "## Steps",
    ]
    md_lines.extend(step_lines or ["- (none)"])
    md_lines.append("")
    md_lines.append("## DAG")
    md_lines.extend(dag_lines or ["- (none)"])
    md_lines.append("")
    md_lines.append("## Barriers")
    if barrier_lines:
        for barrier in barrier_lines:
            md_lines.append(
                f"- {barrier['group_name']} | type={barrier['group_type']} | role={barrier['barrier_role']} | "
                f"steps={', '.join(barrier['step_names']) or '(none)'} | "
                f"used_by={', '.join(barrier['used_by_step_names']) or '(none)'}"
            )
    else:
        md_lines.append("- (none)")
    md_lines.append("")
    md_lines.append("## Root State Semantics")
    md_lines.append(
        f"- awaited_worker_steps: {', '.join(awaited_worker_names) if awaited_worker_names else '(none)'}"
    )
    if awaiting_lines:
        md_lines.extend(f"- {row}" for row in awaiting_lines)
    else:
        md_lines.append("- root does not enter awaiting_worker_result because the plan has no awaited worker steps")
    md_lines.extend(f"- {row}" for row in blocked_conditions)
    md_lines.extend(f"- {row}" for row in failed_conditions)
    md_lines.append("")
    md_lines.append("## Validation Base")
    md_lines.append("```text")
    md_lines.extend(validation_output.splitlines())
    md_lines.append("```")

    artifact_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    print(f"PREFLIGHT_ARTIFACT {artifact_rel}")
PY
)"

printf '%s\n' "$preflight_output"

if [ "$write_artifact" = "true" ]; then
  artifact_rel="$(
    printf '%s\n' "$preflight_output" | awk '/^PREFLIGHT_ARTIFACT / {print $2}' | tail -n 1
  )"
  if [ -n "$artifact_rel" ] && [ -f "$REPO_ROOT/$artifact_rel" ]; then
    ./scripts/validate_markdown_artifact.sh "$REPO_ROOT/$artifact_rel"
  fi
fi
