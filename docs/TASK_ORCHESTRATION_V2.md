# Task Orchestration V2

This document defines the stronger chain orchestration layer for Golem.

The first conditional extension on top of this layer lives in:

```text
docs/TASK_ORCHESTRATION_CONDITIONAL.md
```

## Goal

Allow one root chain to mix:

- local steps
- a real delegated Codex worker step
- richer planning
- smarter final aggregation

The first concrete v2 chain type is:

```text
repo-analysis-worker
```

## New root-level contract

A v2 chain root keeps:

- `chain_type`
- `chain_status`
- `chain_plan`
- `chain_summary`

`chain_plan` is the intended execution contract.

`chain_summary` is the aggregated closure result.

The worker portion of that result is collected explicitly so the root can describe delegated outcomes without relying on manual post-processing.

## Step contract

Each planned step may include:

- `step_name`
- `step_order`
- `task_type`
- `execution_mode`
- `critical`
- `title`
- `objective`
- `depends_on_step_names`
- `status`
- `child_task_id`
- optional runtime fields such as `summary`, `started_at`, `finished_at`

## Execution modes

Supported execution modes in this layer:

- `local`
- `worker`

`local` means Golem runs the step directly with existing scripts.

`worker` means the step materializes as a delegated child task, goes through handoff plus ticket preparation, launches a real controlled Codex run, and returns through the worker result flow.

## Planning

Use:

```text
./scripts/task_chain_plan.sh repo-analysis-worker "<title>"
```

This creates a root `task-chain` task in `planned` chain state and writes a v2 `chain_plan`.

The current default plan is:

1. local self-check
2. delegated repo analysis with real Codex run
3. local comparison artifact after the worker step

The third step is intentionally non-critical so the chain can express warning-grade completion instead of only binary success/failure.

## Running

Use:

```text
./scripts/task_chain_run_v2.sh repo-analysis-worker "<title>"
```

The runner:

1. creates the v2 plan
2. marks the root as running
3. executes the local step
4. creates and delegates a child `repo-analysis` task
5. launches the real Codex run for that child
6. finalizes the worker result
7. executes the trailing local step
8. collects mixed chain results into a root-level snapshot
9. finalizes the root chain with an aggregated artifact

## Status inspection

Use:

```text
./scripts/task_chain_status.sh <root_task_id>
```

This shows:

- root lifecycle state
- `chain_status`
- step counters
- per-step status
- child task ids
- worker evidence when a step used real Codex
- worker outcomes copied into `chain_summary`

## Final aggregation

`./scripts/task_chain_finalize.sh <root_task_id>` now builds a stronger result that considers:

- direct child task outcomes
- step completion vs the planned chain
- `critical` semantics
- warning signals from child outputs
- worker extracted summaries
- worker result outputs and source files
- aggregated artifact paths from the whole chain

The reusable collector is:

```text
./scripts/task_chain_collect_results.sh <root_task_id>
```

The root stores:

- `headline`
- step counters
- local vs worker step counts
- `worker_steps_done`
- `worker_steps_failed`
- `worker_child_ids`
- `worker_result_summaries`
- `worker_outcomes`
- `aggregated_artifact_paths`
- `final_artifact_path`

It also writes a final Markdown artifact under `outbox/manual/`.

## Failure semantics

Rules in this version:

- any failed or incomplete critical step makes the chain fail
- any blocked critical step makes the chain block
- failed non-critical steps degrade the chain to `completed_with_warnings`
- blocked non-critical steps also degrade the chain to `completed_with_warnings`
- warning markers in child outputs also degrade to `completed_with_warnings`

This keeps the root result more expressive than a plain child count.

## Conditional Extension

The v3 conditional layer keeps the same mixed local plus worker model, but lets the root choose one next step after the worker outcome is known.

That layer adds:

- `decision_reason`
- `decision_source_step`
- `next_step_selected`
- `skipped_steps`
- `conditional_outcomes`

It remains intentionally small and does not turn Golem into a generic workflow engine.
