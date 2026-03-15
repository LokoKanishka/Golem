#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/validate_chain_plan.sh <task_id|task_json_path|plan_json_path>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

input_ref="${1:-}"
if [ -z "$input_ref" ]; then
  usage
  fatal "falta task_id o path"
fi

if [ -f "$input_ref" ]; then
  input_path="$input_ref"
elif [ -f "$REPO_ROOT/$input_ref" ]; then
  input_path="$REPO_ROOT/$input_ref"
elif [ -f "$TASKS_DIR/${input_ref}.json" ]; then
  input_path="$TASKS_DIR/${input_ref}.json"
else
  fatal "no existe task/plan en: $input_ref"
fi

python3 - "$input_path" <<'PY'
import json
import pathlib
import sys
from typing import Dict, List, Set


ALLOWED_STEP_STATUS = {
    "",
    "planned",
    "queued",
    "running",
    "delegated",
    "done",
    "failed",
    "blocked",
    "skipped",
}
ALLOWED_EXECUTION_MODES = {"local", "worker"}
ALLOWED_GROUP_TYPES = {"await_group", "join_barrier"}
ALLOWED_SATISFACTION_POLICIES = {"all_done"}
ALLOWED_CONDITIONAL_RESULT_STATUSES = {"done", "failed", "blocked"}


def as_string(value) -> str:
    return str(value if value is not None else "").strip()


def bool_like(value) -> bool:
    return isinstance(value, bool)


def load_source(path: pathlib.Path):
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)

    if not isinstance(data, dict):
        raise ValueError("el documento raiz debe ser un objeto JSON")

    root_task_id = as_string(data.get("task_id"))
    if isinstance(data.get("chain_plan"), dict):
        return data["chain_plan"], "task", root_task_id or path.stem
    return data, "plan", root_task_id or path.stem


def add_error(errors: List[str], message: str):
    if message not in errors:
        errors.append(message)


def add_note(notes: List[str], message: str):
    if message not in notes:
        notes.append(message)


source_path = pathlib.Path(sys.argv[1]).resolve()
errors: List[str] = []
notes: List[str] = []

try:
    plan, source_kind, source_id = load_source(source_path)
except Exception as exc:
    print(f"CHAIN_PLAN_INVALID {source_path}")
    print(f"ERROR: {exc}")
    raise SystemExit(1)

if not isinstance(plan, dict):
    print(f"CHAIN_PLAN_INVALID {source_path}")
    print("ERROR: chain_plan no es un objeto")
    raise SystemExit(1)

plan_kind = as_string(plan.get("plan_kind"))
plan_version = as_string(plan.get("plan_version") or plan.get("version"))
legacy_version = as_string(plan.get("version"))

if not plan_kind:
    plan_kind = "chain_plan"
    add_note(notes, "plan_kind no estaba declarado; se infirio chain_plan por compatibilidad")
elif plan_kind != "chain_plan":
    add_error(errors, f"plan_kind invalido: {plan_kind}")

if not plan_version:
    add_error(errors, "falta plan_version/version")
if not as_string(plan.get("plan_version")) and legacy_version:
    add_note(notes, "plan_version no estaba declarado; se reutilizo version por compatibilidad")

steps = plan.get("steps")
if not isinstance(steps, list) or not steps:
    add_error(errors, "steps debe ser una lista no vacia")
    steps = []

step_by_name: Dict[str, dict] = {}
step_order_seen: Set[int] = set()
dependency_graph: Dict[str, List[str]] = {}
conditional_steps: List[dict] = []
local_count = 0
worker_count = 0
critical_count = 0
await_count = 0

for index, step in enumerate(steps, start=1):
    if not isinstance(step, dict):
        add_error(errors, f"step[{index}] no es un objeto")
        continue

    step_name = as_string(step.get("step_name"))
    if not step_name:
        add_error(errors, f"step[{index}] no tiene step_name")
        continue
    if step_name in step_by_name:
        add_error(errors, f"step_name duplicado: {step_name}")
        continue
    step_by_name[step_name] = step

    step_order = step.get("step_order")
    if not isinstance(step_order, int) or step_order <= 0:
        add_error(errors, f"{step_name}: step_order debe ser entero positivo")
    elif step_order in step_order_seen:
        add_error(errors, f"step_order duplicado: {step_order}")
    else:
        step_order_seen.add(step_order)

    execution_mode = as_string(step.get("execution_mode"))
    if execution_mode not in ALLOWED_EXECUTION_MODES:
        add_error(errors, f"{step_name}: execution_mode invalido: {execution_mode or '(none)'}")
    elif execution_mode == "local":
        local_count += 1
    elif execution_mode == "worker":
        worker_count += 1

    if not bool_like(step.get("critical")):
        add_error(errors, f"{step_name}: critical debe ser booleano")
    elif step.get("critical"):
        critical_count += 1

    if not as_string(step.get("task_type")):
        add_error(errors, f"{step_name}: falta task_type")
    if not as_string(step.get("title")):
        add_error(errors, f"{step_name}: falta title")
    if not as_string(step.get("objective")):
        add_error(errors, f"{step_name}: falta objective")

    step_status = as_string(step.get("status"))
    if step_status not in ALLOWED_STEP_STATUS:
        add_error(errors, f"{step_name}: status invalido: {step_status}")

    depends = step.get("depends_on_step_names")
    if depends is None:
        depends = []
    if not isinstance(depends, list):
        add_error(errors, f"{step_name}: depends_on_step_names debe ser lista")
        depends = []
    normalized_depends: List[str] = []
    seen_depends: Set[str] = set()
    for dep in depends:
        dep_name = as_string(dep)
        if not dep_name:
            add_error(errors, f"{step_name}: depends_on_step_names contiene un valor vacio")
            continue
        if dep_name == step_name:
            add_error(errors, f"{step_name}: un step no puede depender de si mismo")
            continue
        if dep_name in seen_depends:
            add_error(errors, f"{step_name}: depende mas de una vez de {dep_name}")
            continue
        seen_depends.add(dep_name)
        normalized_depends.append(dep_name)
    dependency_graph[step_name] = normalized_depends

    await_worker_result = step.get("await_worker_result", False)
    if not bool_like(await_worker_result):
        add_error(errors, f"{step_name}: await_worker_result debe ser booleano")
        await_worker_result = False
    elif await_worker_result:
        await_count += 1

    await_group = as_string(step.get("await_group"))
    join_group = as_string(step.get("join_group"))
    condition_source_step = as_string(step.get("condition_source_step"))
    run_if_worker_result_status = as_string(step.get("run_if_worker_result_status"))

    if await_worker_result and execution_mode != "worker":
        add_error(errors, f"{step_name}: await_worker_result solo aplica a steps worker")
    if await_group and execution_mode != "worker":
        add_error(errors, f"{step_name}: await_group solo aplica a steps worker")
    if await_group and not await_worker_result:
        add_error(errors, f"{step_name}: await_group requiere await_worker_result=true")
    if join_group and execution_mode != "local":
        add_error(errors, f"{step_name}: join_group solo aplica a steps locales")
    if execution_mode == "worker" and join_group:
        add_error(errors, f"{step_name}: un step worker no puede declarar join_group")

    if condition_source_step or run_if_worker_result_status:
        conditional_steps.append(step)
        if execution_mode != "local":
            add_error(errors, f"{step_name}: la continuacion condicional solo aplica a steps locales")
        if not condition_source_step or not run_if_worker_result_status:
            add_error(errors, f"{step_name}: condition_source_step y run_if_worker_result_status deben declararse juntos")
        elif run_if_worker_result_status not in ALLOWED_CONDITIONAL_RESULT_STATUSES:
            add_error(
                errors,
                f"{step_name}: run_if_worker_result_status invalido: {run_if_worker_result_status}",
            )

if steps and not step_by_name:
    add_error(errors, "no se pudo construir el indice de steps del plan")

for step_name, step in step_by_name.items():
    step_order = step.get("step_order")
    for dep_name in dependency_graph.get(step_name, []):
        if dep_name not in step_by_name:
            add_error(errors, f"{step_name}: depende de un step inexistente: {dep_name}")
            continue
        dep_order = step_by_name[dep_name].get("step_order")
        if isinstance(step_order, int) and isinstance(dep_order, int) and dep_order >= step_order:
            add_error(
                errors,
                f"{step_name}: depende de {dep_name} pero su step_order no es anterior",
            )

    condition_source_step = as_string(step.get("condition_source_step"))
    if condition_source_step:
        if condition_source_step not in step_by_name:
            add_error(errors, f"{step_name}: condition_source_step inexistente: {condition_source_step}")
        else:
            source_mode = as_string(step_by_name[condition_source_step].get("execution_mode"))
            if source_mode != "worker":
                add_error(
                    errors,
                    f"{step_name}: condition_source_step debe apuntar a un step worker, no a {source_mode or '(none)'}",
                )


visiting: Set[str] = set()
visited: Set[str] = set()


def dfs_cycle(node: str):
    if node in visited:
        return
    if node in visiting:
        add_error(errors, f"ciclo detectado en depends_on_step_names alrededor de {node}")
        return
    visiting.add(node)
    for dep in dependency_graph.get(node, []):
        if dep in step_by_name:
            dfs_cycle(dep)
    visiting.remove(node)
    visited.add(node)


for step_name in step_by_name:
    dfs_cycle(step_name)

dependency_groups = plan.get("dependency_groups")
if dependency_groups is None:
    dependency_groups = []
if not isinstance(dependency_groups, list):
    add_error(errors, "dependency_groups debe ser lista")
    dependency_groups = []

group_by_name: Dict[str, dict] = {}
for index, group in enumerate(dependency_groups, start=1):
    if not isinstance(group, dict):
        add_error(errors, f"dependency_groups[{index}] no es un objeto")
        continue
    group_name = as_string(group.get("group_name"))
    if not group_name:
        add_error(errors, f"dependency_groups[{index}] no tiene group_name")
        continue
    if group_name in group_by_name:
        add_error(errors, f"group_name duplicado: {group_name}")
        continue
    group_by_name[group_name] = group

    group_type = as_string(group.get("group_type"))
    if group_type not in ALLOWED_GROUP_TYPES:
        add_error(errors, f"{group_name}: group_type invalido: {group_type or '(none)'}")

    step_names = group.get("step_names")
    if not isinstance(step_names, list) or not step_names:
        add_error(errors, f"{group_name}: step_names debe ser una lista no vacia")
        step_names = []
    normalized_group_steps: List[str] = []
    seen_group_steps: Set[str] = set()
    for step_name in step_names:
        normalized = as_string(step_name)
        if not normalized:
            add_error(errors, f"{group_name}: step_names contiene un valor vacio")
            continue
        if normalized in seen_group_steps:
            add_error(errors, f"{group_name}: step_names repite {normalized}")
            continue
        seen_group_steps.add(normalized)
        normalized_group_steps.append(normalized)
        if normalized not in step_by_name:
            add_error(errors, f"{group_name}: referencia step inexistente: {normalized}")
    group["step_names"] = normalized_group_steps

    satisfaction_policy = as_string(group.get("satisfaction_policy"))
    if satisfaction_policy not in ALLOWED_SATISFACTION_POLICIES:
        add_error(
            errors,
            f"{group_name}: satisfaction_policy invalido: {satisfaction_policy or '(none)'}",
        )

    for flag_name in ("continue_on_blocked", "continue_on_failed"):
        if flag_name in group and not bool_like(group.get(flag_name)):
            add_error(errors, f"{group_name}: {flag_name} debe ser booleano")

    used_by = group.get("used_by_step_names")
    if used_by is None:
        used_by = []
    if not isinstance(used_by, list):
        add_error(errors, f"{group_name}: used_by_step_names debe ser lista")
        used_by = []
    normalized_used_by: List[str] = []
    seen_used_by: Set[str] = set()
    for step_name in used_by:
        normalized = as_string(step_name)
        if not normalized:
            add_error(errors, f"{group_name}: used_by_step_names contiene un valor vacio")
            continue
        if normalized in seen_used_by:
            add_error(errors, f"{group_name}: used_by_step_names repite {normalized}")
            continue
        seen_used_by.add(normalized)
        normalized_used_by.append(normalized)
        if normalized not in step_by_name:
            add_error(errors, f"{group_name}: used_by_step_names refiere step inexistente: {normalized}")
    group["used_by_step_names"] = normalized_used_by

    if group_type == "await_group":
        for step_name in normalized_group_steps:
            step = step_by_name.get(step_name)
            if not step:
                continue
            if as_string(step.get("execution_mode")) != "worker":
                add_error(errors, f"{group_name}: await_group solo puede contener steps worker ({step_name})")
            if not bool(step.get("await_worker_result", False)):
                add_error(errors, f"{group_name}: {step_name} debe tener await_worker_result=true")
            step_await_group = as_string(step.get("await_group"))
            if step_await_group and step_await_group != group_name:
                add_error(errors, f"{group_name}: {step_name} declara await_group={step_await_group}")

for step_name, step in step_by_name.items():
    join_group = as_string(step.get("join_group"))
    await_group = as_string(step.get("await_group"))
    depends = dependency_graph.get(step_name, [])

    if join_group:
        group = group_by_name.get(join_group)
        if group is None:
            add_error(errors, f"{step_name}: join_group inexistente: {join_group}")
        else:
            if as_string(group.get("group_type")) not in {"join_barrier", "await_group"}:
                add_error(errors, f"{step_name}: join_group {join_group} tiene group_type invalido")
            expected_steps = set(group.get("step_names") or [])
            if set(depends) != expected_steps:
                add_error(
                    errors,
                    f"{step_name}: join_group={join_group} no coincide con depends_on_step_names",
                )
            used_by = set(group.get("used_by_step_names") or [])
            if used_by and step_name not in used_by:
                add_error(errors, f"{step_name}: join_group={join_group} no lo incluye en used_by_step_names")

    if await_group:
        group = group_by_name.get(await_group)
        if group is None:
            add_error(errors, f"{step_name}: await_group inexistente: {await_group}")
        else:
            if as_string(group.get("group_type")) != "await_group":
                add_error(errors, f"{step_name}: await_group={await_group} debe apuntar a group_type=await_group")
            if step_name not in set(group.get("step_names") or []):
                add_error(errors, f"{step_name}: await_group={await_group} no lo incluye en step_names")

if conditional_steps:
    decision_steps = [
        step_name
        for step_name, step in step_by_name.items()
        if as_string(step.get("task_type")) == "chain-decision"
    ]
    if len(decision_steps) != 1:
        add_error(errors, "los planes condicionales deben declarar exactamente un step task_type=chain-decision")

declared_counts = {
    "step_count": len(step_by_name),
    "local_step_count": local_count,
    "worker_step_count": worker_count,
    "critical_step_count": critical_count,
    "await_worker_result_step_count": await_count,
    "conditional_step_count": len(conditional_steps),
    "dependency_group_count": len(group_by_name),
}
for field_name, computed in declared_counts.items():
    if field_name in plan:
        value = plan.get(field_name)
        if not isinstance(value, int):
            add_error(errors, f"{field_name} debe ser entero")
        elif value != computed:
            add_error(errors, f"{field_name}={value} no coincide con el valor real {computed}")

if errors:
    print(f"CHAIN_PLAN_INVALID {source_path}")
    print(f"source_kind: {source_kind}")
    print(f"source_id: {source_id or '(none)'}")
    for note in notes:
        print(f"NOTE: {note}")
    for message in errors:
        print(f"ERROR: {message}")
    raise SystemExit(1)

print(f"CHAIN_PLAN_VALID {source_path}")
print(f"source_kind: {source_kind}")
print(f"source_id: {source_id or '(none)'}")
print(f"plan_kind: {plan_kind}")
print(f"plan_version: {plan_version}")
print(f"steps: {len(step_by_name)}")
print(f"local_steps: {local_count}")
print(f"worker_steps: {worker_count}")
print(f"await_worker_steps: {await_count}")
print(f"dependency_groups: {len(group_by_name)}")
print(f"conditional_steps: {len(conditional_steps)}")
for note in notes:
    print(f"NOTE: {note}")
PY
