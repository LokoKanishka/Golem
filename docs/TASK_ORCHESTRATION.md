# Task Orchestration

This document now describes two orchestration layers in Golem:

- the original minimal parent/dependency layer
- the stronger v2 chain layer with explicit steps, mixed local plus worker execution, and richer root aggregation

The detailed v2 contract lives in `docs/TASK_ORCHESTRATION_V2.md`.

## Shared relationship fields

Tasks may include:

- `parent_task_id`
- `depends_on`

These fields are still structural. They do not add scheduling by themselves.

## Step-aware task metadata

Child tasks that belong to an explicit chain step may also include:

- `step_name`
- `step_order`
- `critical`
- `execution_mode`

Those fields let Golem keep the child task and the root `chain_plan` aligned.

## Minimal child creation

Use:

```text
./scripts/task_spawn_child.sh <parent_task_id> <type> "<title>"
```

Optional environment variables now allow step-aware children:

```text
TASK_CHILD_DEPENDS_ON='["task-a"]'
TASK_CHILD_OBJECTIVE="..."
TASK_CHILD_STEP_NAME="delegated-repo-analysis"
TASK_CHILD_STEP_ORDER=2
TASK_CHILD_CRITICAL=true
TASK_CHILD_EXECUTION_MODE=worker
./scripts/task_spawn_child.sh <parent_task_id> repo-analysis "<title>"
```

## Inspect the tree

Use:

```text
./scripts/task_tree.sh <task_id>
```

The tree now shows step metadata when present, so mixed local-worker chains are easier to inspect.

## Original demo runner

The original demo runner remains:

```text
./scripts/task_chain_run.sh self-check-compare "<title>"
```

That path is still useful as the smallest orchestration baseline.

## Stronger v2 chain flow

The new v2 chain flow adds:

- explicit planning before execution
- step ordering inside `chain_plan`
- critical vs non-critical steps
- mixed `local` and `worker` execution modes in one chain
- a richer root `chain_summary`
- a final chain artifact that aggregates the whole execution

Main entrypoints:

```text
./scripts/task_chain_plan.sh repo-analysis-worker "<title>"
./scripts/task_chain_run_v2.sh repo-analysis-worker "<title>"
./scripts/task_chain_status.sh <root_task_id>
./scripts/task_chain_summary.sh <root_task_id>
```

## Why v2 matters

The root chain is no longer just a shell around child tasks.

It now persists:

- the intended step sequence
- the execution mode of each step
- whether a failed step should fail the chain
- which child task fulfilled each step
- a stronger aggregate result at the end

That makes a mixed local plus delegated chain inspectable without pretending to be a full scheduler.
