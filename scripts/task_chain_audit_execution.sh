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
  ./scripts/task_chain_audit_execution.sh <root_task_id|task_json_path> [--artifact]
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

traceability_env="$(
  python3 - "$root_task_path" <<'PY'
import json
import pathlib
import shlex
import sys

task_path = pathlib.Path(sys.argv[1])
task = json.loads(task_path.read_text(encoding="utf-8"))
values = {
    "TASK_TYPE": task.get("type", ""),
    "EFFECTIVE_PLAN_PATH": task.get("effective_plan_path", ""),
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"
eval "$traceability_env"

[ "$TASK_TYPE" = "task-chain" ] || fatal "la tarea indicada no es type=task-chain"

validation_output=""
validation_exit=0
if [ -n "$EFFECTIVE_PLAN_PATH" ] && [ -f "$REPO_ROOT/$EFFECTIVE_PLAN_PATH" ]; then
  set +e
  validation_output="$(cd "$REPO_ROOT" && ./scripts/validate_chain_plan.sh "$EFFECTIVE_PLAN_PATH" 2>&1)"
  validation_exit="$?"
  set -e
fi

summary_json="$(cd "$REPO_ROOT" && ./scripts/task_chain_collect_results.sh "$root_task_id")"

mkdir -p "$OUTBOX_DIR"

audit_output="$(
python3 - "$REPO_ROOT" "$root_task_path" "$summary_json" "$write_artifact" "$validation_exit" "$validation_output" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import sys


WAITING_STATUSES = {"planned", "running", "delegated"}
TERMINAL_ROOT_STATUSES = {"done", "failed", "blocked"}
CHECKED_STEP_FIELDS = [
    "step_order",
    "task_type",
    "execution_mode",
    "critical",
    "title",
    "objective",
    "depends_on_step_names",
    "await_worker_result",
    "await_group",
    "join_group",
    "condition_source_step",
    "run_if_worker_result_status",
]


def as_string(value) -> str:
    return str(value if value is not None else "").strip()


def bool_value(value) -> bool:
    return bool(value)


def comparable_value(field_name: str, value):
    if field_name in {
        "await_group",
        "join_group",
        "condition_source_step",
        "run_if_worker_result_status",
    }:
        return as_string(value)
    if field_name == "depends_on_step_names":
        return value or []
    if field_name == "await_worker_result":
        return bool_value(value)
    return value


def iso_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "chain-audit"


repo_root = pathlib.Path(sys.argv[1]).resolve()
root_task_path = pathlib.Path(sys.argv[2]).resolve()
summary = json.loads(sys.argv[3])
write_artifact = sys.argv[4] == "true"
validation_exit = int(sys.argv[5])
validation_output = sys.argv[6]

root = json.loads(root_task_path.read_text(encoding="utf-8"))
root_task_id = as_string(root.get("task_id")) or root_task_path.stem
title = as_string(root.get("title")) or root_task_id
generated_at = iso_now()

warnings = []
failures = []
notes = []

effective_plan_path = as_string(root.get("effective_plan_path"))
effective_plan_abs = (repo_root / effective_plan_path).resolve() if effective_plan_path else pathlib.Path("")
effective_plan_sha256_expected = as_string(root.get("effective_plan_sha256"))
effective_chain_plan = root.get("effective_chain_plan") if isinstance(root.get("effective_chain_plan"), dict) else {}
preflight_artifact_path = as_string(root.get("preflight_artifact_path"))
preflight_sha256 = as_string(root.get("preflight_sha256"))
validated_plan_version = as_string(root.get("validated_plan_version"))
validated_at = as_string(root.get("validated_at"))
preflighted_at = as_string(root.get("preflighted_at"))
root_chain_summary = root.get("chain_summary") if isinstance(root.get("chain_summary"), dict) else {}
final_artifact_path = as_string(summary.get("final_artifact_path")) or as_string(root_chain_summary.get("final_artifact_path"))

effective_plan = {}
effective_plan_hash_actual = ""
effective_plan_hash_match = "unknown"
traceability_mode = "strong"

if not effective_plan_path:
    traceability_mode = "insufficient_traceability"
    warnings.append("root no declara effective_plan_path")
elif not effective_plan_abs.is_file():
    failures.append(f"effective plan artifact no existe: {effective_plan_path}")
else:
    raw = effective_plan_abs.read_bytes()
    effective_plan_hash_actual = hashlib.sha256(raw).hexdigest()
    try:
        effective_plan = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        failures.append(f"effective plan artifact no es JSON valido: {exc}")
        effective_plan = {}
    if effective_plan_sha256_expected:
        if effective_plan_sha256_expected == effective_plan_hash_actual:
            effective_plan_hash_match = "yes"
        else:
            effective_plan_hash_match = "no"
            failures.append(
                "effective_plan_sha256 no coincide con el artifact persistido "
                f"({effective_plan_sha256_expected} != {effective_plan_hash_actual})"
            )
    else:
        effective_plan_hash_match = "missing_expected_hash"
        warnings.append("root no declara effective_plan_sha256")

if effective_chain_plan and effective_plan:
    if json.dumps(effective_chain_plan, sort_keys=True) != json.dumps(effective_plan, sort_keys=True):
        failures.append("effective_chain_plan embebido no coincide con effective_plan_path")
elif effective_plan and not effective_chain_plan:
    warnings.append("root no embebe effective_chain_plan aunque el artifact existe")

if validation_exit != 0 and effective_plan_path:
    failures.append("effective plan persistido no valida contra CHAIN_PLAN_CONTRACT")

runtime_plan = root.get("chain_plan") if isinstance(root.get("chain_plan"), dict) else {}
runtime_steps = runtime_plan.get("steps") if isinstance(runtime_plan.get("steps"), list) else []
runtime_steps_by_name = {
    as_string(step.get("step_name")): step
    for step in runtime_steps
    if isinstance(step, dict) and as_string(step.get("step_name"))
}

effective_steps = effective_plan.get("steps") if isinstance(effective_plan.get("steps"), list) else []
effective_steps_by_name = {
    as_string(step.get("step_name")): step
    for step in effective_steps
    if isinstance(step, dict) and as_string(step.get("step_name"))
}

observed_steps = summary.get("step_results") if isinstance(summary.get("step_results"), list) else []
observed_steps_by_name = {
    as_string(step.get("step_name")): step
    for step in observed_steps
    if isinstance(step, dict) and as_string(step.get("step_name"))
}

barriers = summary.get("dependency_barriers") if isinstance(summary.get("dependency_barriers"), list) else []
barriers_by_name = {
    as_string(barrier.get("group_name")): barrier
    for barrier in barriers
    if isinstance(barrier, dict) and as_string(barrier.get("group_name"))
}

if not effective_steps_by_name and traceability_mode == "strong":
    failures.append("effective plan persistido no contiene steps auditables")

extra_runtime_steps = sorted(name for name in runtime_steps_by_name if name not in effective_steps_by_name)
if extra_runtime_steps:
    failures.append("runtime chain_plan contiene steps fuera del effective plan: " + ", ".join(extra_runtime_steps))

step_audit_rows = []
for step_name, effective_step in sorted(
    effective_steps_by_name.items(),
    key=lambda item: (int(item[1].get("step_order", 0) or 0), item[0]),
):
    runtime_step = runtime_steps_by_name.get(step_name)
    observed_step = observed_steps_by_name.get(step_name)
    status = as_string((observed_step or {}).get("status"))
    step_failures = []
    step_warnings = []

    if runtime_step is None:
        step_failures.append("runtime chain_plan no contiene este step")
    if observed_step is None:
        step_failures.append("collector no devolvio estado observado para este step")

    if runtime_step is not None:
        for field_name in CHECKED_STEP_FIELDS:
            expected_value = comparable_value(field_name, effective_step.get(field_name))
            observed_value = comparable_value(field_name, runtime_step.get(field_name))
            if expected_value != observed_value:
                step_failures.append(
                    f"runtime {field_name} drift: expected={expected_value!r} observed={observed_value!r}"
                )

    if observed_step is not None:
        dependencies = effective_step.get("depends_on_step_names") or []
        dependency_statuses = {
            dep: as_string((observed_steps_by_name.get(dep) or {}).get("status")) or "missing"
            for dep in dependencies
        }
        join_group = as_string(effective_step.get("join_group"))
        barrier = barriers_by_name.get(join_group) if join_group else None
        child_task_id = as_string(observed_step.get("child_task_id"))
        worker_result_status = as_string(observed_step.get("worker_result_status"))
        execution_mode = as_string(effective_step.get("execution_mode"))
        await_worker_result = bool_value(effective_step.get("await_worker_result"))

        if execution_mode == "worker" and status != "planned" and not child_task_id:
            step_failures.append("step worker sin child_task_id observable")
        if await_worker_result and status in {"done", "failed", "blocked"} and not worker_result_status:
            step_failures.append("worker awaitable terminal sin worker_result_status")
        if await_worker_result and status == "done" and worker_result_status != "done":
            step_failures.append(
                f"worker awaitable done pero worker_result_status={worker_result_status or '(none)'}"
            )
        if await_worker_result and status == "failed" and worker_result_status != "failed":
            step_failures.append(
                f"worker awaitable failed pero worker_result_status={worker_result_status or '(none)'}"
            )
        if await_worker_result and status == "blocked" and worker_result_status != "blocked":
            step_failures.append(
                f"worker awaitable blocked pero worker_result_status={worker_result_status or '(none)'}"
            )

        if execution_mode == "local" and status in {"running", "done"}:
            blocked_dependencies = [
                name for name, dep_status in dependency_statuses.items() if dep_status != "done"
            ]
            if blocked_dependencies:
                step_failures.append(
                    "step local corrio antes de que sus dependencias estuvieran done: "
                    + ", ".join(f"{name}={dependency_statuses[name]}" for name in blocked_dependencies)
                )
            if barrier and as_string(barrier.get("status")) != "satisfied":
                step_failures.append(
                    f"step local corrio antes de satisfacer barrier {join_group} ({as_string(barrier.get('status')) or '(none)'})"
                )

        if execution_mode == "local" and status == "skipped":
            if barrier:
                if as_string(barrier.get("status")) not in {"failed", "blocked"}:
                    step_failures.append(
                        f"step skipped sin barrier terminal coherente: {join_group}={as_string(barrier.get('status')) or '(none)'}"
                    )
            else:
                if not any(dep_status in {"failed", "blocked", "skipped"} for dep_status in dependency_statuses.values()):
                    step_failures.append("step skipped sin dependencia failed/blocked/skipped que lo explique")

        if status == "planned" and summary.get("final_task_status") in TERMINAL_ROOT_STATUSES:
            step_failures.append("step quedo planned aunque la root ya es terminal")
        elif status in WAITING_STATUSES and summary.get("final_task_status") in TERMINAL_ROOT_STATUSES:
            step_failures.append("step quedo en estado no terminal aunque la root ya es terminal")

        runtime_started_at = as_string((runtime_step or {}).get("started_at"))
        if execution_mode == "local" and runtime_started_at:
            for dep in dependencies:
                dep_runtime = runtime_steps_by_name.get(dep) or {}
                dep_finished_at = as_string(dep_runtime.get("finished_at"))
                if dep_finished_at and dep_finished_at > runtime_started_at:
                    step_failures.append(
                        f"step local comenzo antes de que terminara su dependencia {dep}"
                    )

        if barrier and execution_mode == "local":
            barrier_status = as_string(barrier.get("status"))
            if status == "planned" and barrier_status in {"failed", "blocked"}:
                step_warnings.append(
                    f"step sigue planned aunque barrier {join_group} ya esta {barrier_status}; resume deberia poder saltarlo"
                )

    step_audit_rows.append(
        {
            "step_name": step_name,
            "step_order": effective_step.get("step_order"),
            "status": status or "(missing)",
            "failures": step_failures,
            "warnings": step_warnings,
        }
    )
    failures.extend(f"{step_name}: {message}" for message in step_failures)
    warnings.extend(f"{step_name}: {message}" for message in step_warnings)

for barrier_name, barrier in sorted(barriers_by_name.items()):
    barrier_status = as_string(barrier.get("status"))
    step_states = {row.get("step_name", ""): as_string(row.get("status")) for row in barrier.get("step_states") or []}
    done_names = sorted(name for name, status in step_states.items() if status == "done")
    waiting_names = sorted(name for name, status in step_states.items() if status in WAITING_STATUSES)
    failed_names = sorted(name for name, status in step_states.items() if status == "failed")
    blocked_names = sorted(name for name, status in step_states.items() if status == "blocked")
    skipped_names = sorted(name for name, status in step_states.items() if status == "skipped")
    continue_on_blocked = bool_value(barrier.get("continue_on_blocked"))
    continue_on_failed = bool_value(barrier.get("continue_on_failed"))
    step_names = barrier.get("step_names") or []

    expected_barrier_status = "waiting"
    if failed_names and not continue_on_failed:
        expected_barrier_status = "failed"
    elif blocked_names and not continue_on_blocked:
        expected_barrier_status = "blocked"
    elif skipped_names and not continue_on_failed:
        expected_barrier_status = "failed"
    elif step_names and len(done_names) == len(step_names):
        expected_barrier_status = "satisfied"

    if barrier_status != expected_barrier_status:
        failures.append(
            f"barrier {barrier_name}: status observado {barrier_status or '(none)'} no coincide con el esperado {expected_barrier_status}"
        )

observed_chain_status = as_string(root.get("chain_status"))
expected_chain_status = as_string(summary.get("chain_status"))
observed_root_status = as_string(root.get("status"))
expected_root_status = as_string(summary.get("final_task_status"))

if observed_chain_status != expected_chain_status:
    failures.append(
        f"chain_status incoherente: root={observed_chain_status or '(none)'} summary={expected_chain_status or '(none)'}"
    )
if observed_root_status != expected_root_status:
    failures.append(
        f"root status incoherente: root={observed_root_status or '(none)'} summary={expected_root_status or '(none)'}"
    )

if expected_chain_status == "awaiting_worker_result" and observed_root_status != "delegated":
    failures.append("root deberia seguir delegated mientras chain_status=awaiting_worker_result")
if expected_chain_status == "blocked" and observed_root_status != "blocked":
    failures.append("root blocked esperado pero status real distinto")
if expected_chain_status == "failed" and observed_root_status != "failed":
    failures.append("root failed esperado pero status real distinto")

if not failures:
    if traceability_mode == "insufficient_traceability":
        audit_status = "WARN"
        audit_reason = "insufficient_traceability"
    elif observed_root_status not in TERMINAL_ROOT_STATUSES or expected_chain_status == "awaiting_worker_result":
        audit_status = "WARN"
        audit_reason = "execution_incomplete"
    else:
        audit_status = "OK"
        audit_reason = "execution_coherent"
else:
    audit_status = "FAIL"
    audit_reason = "execution_drift"

lines = []
lines.append(f"CHAIN_EXECUTION_AUDIT_{audit_status} {root_task_path}")
lines.append(f"root_task_id: {root_task_id}")
lines.append(f"audit_status: {audit_status}")
lines.append(f"audit_reason: {audit_reason}")
lines.append(f"title: {title}")
lines.append(f"root_status: {observed_root_status or '(none)'}")
lines.append(f"expected_root_status: {expected_root_status or '(none)'}")
lines.append(f"chain_status: {observed_chain_status or '(none)'}")
lines.append(f"expected_chain_status: {expected_chain_status or '(none)'}")
lines.append(f"validated_plan_version: {validated_plan_version or '(none)'}")
lines.append(f"effective_plan_path: {effective_plan_path or '(none)'}")
lines.append(f"effective_plan_sha256_expected: {effective_plan_sha256_expected or '(none)'}")
lines.append(f"effective_plan_sha256_actual: {effective_plan_hash_actual or '(none)'}")
lines.append(f"effective_plan_hash_match: {effective_plan_hash_match}")
lines.append(f"preflight_artifact_path: {preflight_artifact_path or '(none)'}")
lines.append(f"preflight_sha256: {preflight_sha256 or '(none)'}")
lines.append(f"validated_at: {validated_at or '(none)'}")
lines.append(f"preflighted_at: {preflighted_at or '(none)'}")
lines.append(f"step_count: {len(effective_steps_by_name)}")
lines.append(f"steps_observed: {len(observed_steps_by_name)}")
lines.append(f"barrier_count: {len(barriers_by_name)}")
lines.append(f"warning_count: {len(warnings)}")
lines.append(f"failure_count: {len(failures)}")
lines.append("")
lines.append("## Step Audit")
for row in step_audit_rows:
    lines.append(
        f"- [{row['step_order']}] {row['step_name']} | status={row['status']} | "
        f"failures={len(row['failures'])} | warnings={len(row['warnings'])}"
    )
lines.append("")
lines.append("## Findings")
if warnings:
    lines.append("WARNINGS:")
    lines.extend(f"- {message}" for message in warnings)
else:
    lines.append("WARNINGS:")
    lines.append("- (none)")
if failures:
    lines.append("FAILURES:")
    lines.extend(f"- {message}" for message in failures)
else:
    lines.append("FAILURES:")
    lines.append("- (none)")
lines.append("")
lines.append("## Summary Basis")
lines.append(f"- headline: {as_string(summary.get('headline')) or '(none)'}")
lines.append(f"- final_artifact_path: {final_artifact_path or '(none)'}")
lines.append(
    "- dependency_barriers: "
    + (", ".join(f"{name}={as_string(barriers_by_name[name].get('status'))}" for name in sorted(barriers_by_name)) or "(none)")
)

output_text = "\n".join(lines)
print(output_text)

if write_artifact:
    artifact_rel = "outbox/manual/{ts}-{slug}-chain-execution-audit.md".format(
        ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        slug=slugify(title),
    )
    artifact_path = repo_root / artifact_rel
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    md_lines = [
        "# Chain Execution Audit",
        "",
        f"generated_at: {generated_at}",
        f"repo: {repo_root.as_posix()}",
        "task_type: chain-execution-audit",
        f"root_task_id: {root_task_id}",
        f"audit_status: {audit_status}",
        f"audit_reason: {audit_reason}",
        f"effective_plan_path: {effective_plan_path or '(none)'}",
        "",
        "## Summary",
        f"- title: {title}",
        f"- root_status: {observed_root_status or '(none)'}",
        f"- expected_root_status: {expected_root_status or '(none)'}",
        f"- chain_status: {observed_chain_status or '(none)'}",
        f"- expected_chain_status: {expected_chain_status or '(none)'}",
        f"- validated_plan_version: {validated_plan_version or '(none)'}",
        f"- effective_plan_sha256_expected: {effective_plan_sha256_expected or '(none)'}",
        f"- effective_plan_sha256_actual: {effective_plan_hash_actual or '(none)'}",
        f"- effective_plan_hash_match: {effective_plan_hash_match}",
        f"- preflight_artifact_path: {preflight_artifact_path or '(none)'}",
        "",
        "## Step Audit",
    ]
    md_lines.extend(
        f"- [{row['step_order']}] {row['step_name']} | status={row['status']} | failures={len(row['failures'])} | warnings={len(row['warnings'])}"
        for row in step_audit_rows
    )
    md_lines.append("")
    md_lines.append("## Warnings")
    md_lines.extend(f"- {message}" for message in warnings) if warnings else md_lines.append("- (none)")
    md_lines.append("")
    md_lines.append("## Failures")
    md_lines.extend(f"- {message}" for message in failures) if failures else md_lines.append("- (none)")
    md_lines.append("")
    md_lines.append("## Summary Basis")
    md_lines.append(f"- headline: {as_string(summary.get('headline')) or '(none)'}")
    md_lines.append(f"- final_artifact_path: {final_artifact_path or '(none)'}")
    md_lines.append(
        "- dependency_barriers: "
        + (", ".join(f"{name}={as_string(barriers_by_name[name].get('status'))}" for name in sorted(barriers_by_name)) or "(none)")
    )
    if validation_output:
        md_lines.append("")
        md_lines.append("## Validation Base")
        md_lines.append("```text")
        md_lines.extend(validation_output.splitlines())
        md_lines.append("```")

    artifact_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    print(f"AUDIT_ARTIFACT {artifact_rel}")
PY
)"

printf '%s\n' "$audit_output"

if [ "$write_artifact" = "true" ]; then
  artifact_rel="$(
    printf '%s\n' "$audit_output" | awk '/^AUDIT_ARTIFACT / {print $2}' | tail -n 1
  )"
  if [ -n "$artifact_rel" ] && [ -f "$REPO_ROOT/$artifact_rel" ]; then
    "$VALIDATE_MARKDOWN" "$REPO_ROOT/$artifact_rel" >/dev/null
  fi
fi

audit_status="$(printf '%s\n' "$audit_output" | sed -n 's/^audit_status: //p' | tail -n 1)"
case "$audit_status" in
  OK) exit 0 ;;
  WARN) exit 3 ;;
  FAIL) exit 1 ;;
  *) exit 1 ;;
esac
