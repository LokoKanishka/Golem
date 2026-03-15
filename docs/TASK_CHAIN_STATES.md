# Task Chain States

This document defines the first explicit internal states for chain root tasks in Golem.

## Why `chain_status` exists

The general task `status` is still useful and should stay small:

- `queued`
- `running`
- `blocked`
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
- `awaiting_worker_result`
- `completed`
- `completed_with_warnings`
- `blocked`
- `failed`

V2 chains also track step-level runtime state inside `chain_plan.steps[*].status`.

Current practical values are:

- `planned`
- `running`
- `delegated`
- `done`
- `blocked`
- `failed`
- `skipped`

## Difference between task status and chain status

Use task `status` for the high-level lifecycle outcome of the root task.

Use `chain_status` for the internal orchestration outcome of the chain.

Typical mappings in this version:

- `status: done` + `chain_status: completed`
- `status: done` + `chain_status: completed_with_warnings`
- `status: delegated` + `chain_status: awaiting_worker_result`
- `status: blocked` + `chain_status: blocked`
- `status: failed` + `chain_status: failed`

## What the root task summarizes

The chain root should persist an aggregated summary of its direct children, including:

- `child_task_ids`
- `child_count`
- `children_done`
- `children_failed`
- `children_blocked`
- `children_delegated`
- `children_running`
- `children_with_warnings`
- aggregated child artifact paths

This version stores that summary in the root task under `chain_summary` and also persists a `chain-summary` output entry.

The stronger v2 summary may also include:

- `step_count`
- `steps_completed`
- `steps_failed`
- `steps_blocked`
- `steps_delegated`
- `steps_running`
- `steps_pending`
- `critical_step_count`
- `critical_steps_failed`
- `critical_steps_blocked`
- `local_step_count`
- `worker_step_count`
- `local_steps_count`
- `delegated_steps_count`
- `worker_steps_done`
- `worker_steps_blocked`
- `worker_steps_delegated`
- `worker_steps_running`
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
- critical blocked steps block the chain
- worker steps marked `await_worker_result` leave the root in `status: delegated` + `chain_status: awaiting_worker_result` while one or more awaited worker results are still pending
- once delegated children have a formal worker result, `task_chain_resume.sh` updates every resolved worker step and re-enters the chain from the root
- a critical worker result of `failed` closes the root as `failed`
- a critical worker result of `blocked` closes the root as `blocked`
- a worker result of `done` allows any dependent local step to run only when all of that step's dependencies are also `done`
- if a dependency is still waiting, the dependent local step stays planned
- if a dependency ended as `failed`, `blocked`, or `skipped`, the dependent local step becomes `skipped`
- non-critical failed steps produce `completed_with_warnings`
- non-critical blocked steps also produce `completed_with_warnings`
- incomplete critical steps also fail the chain at finalization time

That means:

- if any child fails, the root chain closes as `failed`
- if no critical child failed but a critical child is `blocked`, the root chain closes as `blocked`
- if one or more critical worker steps are intentionally awaiting manual-controlled result, the root chain closes as `delegated`
- the root task records the failure in `chain_status`
- the aggregated summary shows failed vs blocked child counts separately
- the aggregated summary also shows which awaited worker children are still pending and which already resolved
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
