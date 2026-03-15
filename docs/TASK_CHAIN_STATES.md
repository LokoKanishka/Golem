# Task Chain States

This document defines the first explicit internal states for chain root tasks in Golem.

## Why `chain_status` exists

The general task `status` is still useful and should stay small:

- `queued`
- `running`
- `delegated`
- `done`
- `failed`
- `cancelled`

But a chain root needs more semantic detail than that.

Example:

- `status: done`
- `chain_status: completed_with_warnings`

That means the chain finished and closed coherently, but one or more child tasks reported warning-level signals.

## Supported `chain_status` values

- `planned`
- `running`
- `completed`
- `completed_with_warnings`
- `failed`

V2 chains also track step-level runtime state inside `chain_plan.steps[*].status`.

Current practical values are:

- `planned`
- `running`
- `done`
- `failed`
- `skipped`

## Difference between task status and chain status

Use task `status` for the high-level lifecycle outcome of the root task.

Use `chain_status` for the internal orchestration outcome of the chain.

Typical mappings in this version:

- `status: done` + `chain_status: completed`
- `status: done` + `chain_status: completed_with_warnings`
- `status: failed` + `chain_status: failed`

## What the root task summarizes

The chain root should persist an aggregated summary of its direct children, including:

- `child_task_ids`
- `child_count`
- `children_done`
- `children_failed`
- `children_with_warnings`
- aggregated child artifact paths

This version stores that summary in the root task under `chain_summary` and also persists a `chain-summary` output entry.

The stronger v2 summary may also include:

- `step_count`
- `steps_completed`
- `steps_failed`
- `steps_pending`
- `critical_step_count`
- `critical_steps_failed`
- `local_step_count`
- `worker_step_count`
- `local_steps_count`
- `delegated_steps_count`
- `worker_steps_done`
- `worker_steps_failed`
- `worker_child_ids`
- `worker_result_summaries`
- `worker_outcomes`
- `aggregated_artifact_paths`
- `decision_reason`
- `decision_source_step`
- `next_step_selected`
- `skipped_steps`
- `conditional_outcomes`
- `headline`
- `final_artifact_path`

## Failure behavior

In this version, all children in the demo chains are treated as critical.

In v2 this becomes step-aware:

- critical steps fail the chain
- non-critical failed steps produce `completed_with_warnings`
- incomplete critical steps also fail the chain at finalization time

That means:

- if any child fails, the root chain closes as `failed`
- the root task records the failure in `chain_status`
- the aggregated summary shows the failed child count
- the final artifact still gets generated for traceability

## Final chain artifact

Each chain run generates a final Markdown artifact under `outbox/manual/`.

The artifact includes at least:

- H1
- `generated_at`
- `root_task_id`
- `chain_type`
- summary
- child task list
- final result
- notes
- aggregated child artifacts
- step-by-step execution trace
- worker evidence when the chain included delegated execution
- worker outcomes copied into the root summary and final artifact
- conditional outcomes and skipped-step evidence when the chain made a runtime decision

The artifact must pass:

```text
./scripts/validate_markdown_artifact.sh <path>
```

## Why this is not a workflow engine

This layer improves traceability and closure semantics, but it still does not add:

- scheduling
- retries
- queue management
- automatic ordering beyond the runner itself
- parallel orchestration

It only makes the chain root more honest and inspectable.
