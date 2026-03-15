# Task Chain Results

This document defines how a v2 mixed chain collects and persists aggregated results at the root task level.

## Goal

When a chain mixes local execution with a delegated real Codex worker step, the root should not rely on a manual wrap-up to explain what happened.

Instead, the root should collect:

- local step outcomes
- delegated worker outcomes
- worker result summaries
- aggregated artifact paths
- a final chain artifact that already includes the worker evidence

## Collector

Use:

```text
./scripts/task_chain_collect_results.sh <root_task_id>
```

The collector reads:

- the root `chain_plan`
- direct child tasks
- child artifacts
- `worker_run`
- the latest `worker-result` output when a worker step exists
- persisted root decision data when a conditional chain already chose the next step

It returns one JSON summary that the finalizer and runner can reuse.

## Minimum Root `chain_summary`

For v2 chains, the root should persist at least:

- `delegated_steps_count`
- `local_steps_count`
- `worker_steps_done`
- `worker_steps_failed`
- `worker_result_summaries`
- `aggregated_artifact_paths`
- `worker_outcomes`
- `headline`
- `final_artifact_path`

Conditional chains extend that summary with:

- `decision_reason`
- `decision_source_step`
- `next_step_selected`
- `skipped_steps`
- `conditional_outcomes`

Compatibility fields may stay in parallel:

- `local_step_count`
- `worker_step_count`
- `artifact_paths`

## `worker_result_summaries`

`worker_result_summaries` is the ordered list of compact worker summaries incorporated into the root.

Preferred sources, in order:

1. `worker-result.summary`
2. `worker-result.extracted_summary`
3. `worker_run.extracted_summary`

This lets the root carry a durable semantic summary instead of only raw runtime evidence.

## `worker_outcomes`

`worker_outcomes` is the clearer per-delegated-step section persisted in the root summary.

Each entry should carry enough data to explain the worker part of the chain without reopening the child task first, including:

- `step_name`
- `step_order`
- `child_task_id`
- `status`
- `worker_state`
- `worker_result_status`
- `summary`
- `result_artifact_path`
- `result_source_files`
- `artifact_paths`

## Aggregated Artifact Paths

`aggregated_artifact_paths` should deduplicate the useful artifact set collected from all chain steps.

For worker steps this should include the normalized worker result artifact when present, even if the operator mainly inspects the root final artifact later.

## Final Chain Artifact

The chain final artifact should now include:

- `## Summary`
- `## Chain Plan`
- `## Worker Outcomes`
- `## Conditional Outcomes` when the chain made a runtime decision
- `## Result`
- `## Aggregated Artifacts`
- `## Notes`

This keeps the worker contribution visible in the root deliverable instead of only in the child task.

## Runner Interaction

`task_chain_run_v2.sh` may record a pre-finalization `chain-results-collected` output so the root already shows the collected counts and worker summaries before closure.

`task_chain_run_v3.sh` does the same, but includes the decision fields and skipped-step evidence.

The final persisted closure still happens in:

```text
./scripts/task_chain_finalize.sh <root_task_id>
```

## Why This Matters

This version keeps mixed chains:

- more self-describing
- less dependent on manual interpretation
- easier to audit from the root task alone
- better aligned with durable worker-result artifacts
