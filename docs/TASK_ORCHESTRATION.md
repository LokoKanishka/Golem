# Task Orchestration

This document defines the first minimal orchestration layer between Golem tasks.

## What "minimal orchestration" means

In this version, orchestration means only:

- relating a task to a parent task
- declaring simple dependencies
- making child task creation explicit
- running a short, honest demo chain that coordinates more than one task
- leaving the root chain with an aggregated summary and final artifact

This layer is intentionally small.

## New relationship fields

Tasks may now include:

- `parent_task_id`
- `depends_on`

`parent_task_id` is the direct parent task when a task belongs to a larger objective.

`depends_on` is a list of task ids that should be considered predecessors from an orchestration point of view.

Example:

```json
{
  "task_id": "task-20260313T220608Z-5e26f38b",
  "type": "compare-files",
  "parent_task_id": "task-20260313T220000Z-root",
  "depends_on": ["task-20260313T220500Z-selfcheck"],
  "status": "done"
}
```

## What this version does not support

This version does not provide:

- a scheduler
- automatic execution ordering
- parallelism
- queueing
- retries
- real workflow definitions
- automatic Codex execution

The fields are structural, not operational policy engines.

## Create a child task

Use:

```text
./scripts/task_spawn_child.sh <parent_task_id> <type> "<title>"
```

The script:

1. verifies that the parent task exists
2. creates a new child task
3. sets `parent_task_id`
4. initializes `depends_on` with the parent task id

## Inspect a task relationship tree

Use:

```text
./scripts/task_tree.sh <task_id>
```

The output is intentionally simple:

- parent
- current task
- declared dependencies
- direct children

## Demo chain

Use:

```text
./scripts/task_chain_run.sh self-check-compare "<title>"
```

For controlled failure validation:

```text
./scripts/task_chain_run.sh self-check-compare-fail "<title>"
```

The demo chain is:

1. create a root task of type `task-chain`
2. run a child `self-check`
3. run a child `compare-files`
4. aggregate child results on the root task
5. generate a final Markdown artifact for the chain
6. close the root task as `done` or `failed`

## Why the demo uses `self-check-compare`

`self-check-artifact` would depend on live browser tabs, which makes the demonstration too fragile for a baseline orchestration layer.

`self-check-compare` is a safer real chain because:

- `self-check` exercises existing live capability checks
- `compare-files` is local, deterministic, and low risk
- the chain still proves that Golem can coordinate multiple related tasks

The failure validation variant uses the same shape but points the compare step at a deliberately missing file. That keeps the failure path honest, local, and predictable.

## Why this is the step before stronger orchestration

Before adding scheduling or workflows, Golem needs a stable way to say:

- which task belongs to which parent objective
- which task depends on which previous task
- how to inspect a small task tree

This layer gives that structure without pretending to solve full orchestration yet.
