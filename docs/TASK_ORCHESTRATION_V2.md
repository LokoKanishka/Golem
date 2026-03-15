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

The first concrete v2 chain types are:

```text
repo-analysis-worker
repo-analysis-worker-manual
repo-analysis-worker-manual-multi
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
- `join_group`
- `await_group`
- `await_worker_result`
- `status`
- `child_task_id`
- optional runtime fields such as `summary`, `started_at`, `finished_at`

`chain_plan` may also declare `dependency_groups` so multi-worker continuation is expressed as an explicit join/await barrier contract instead of only an implied ordering rule.

## Execution modes

Supported execution modes in this layer:

- `local`
- `worker`

`local` means Golem runs the step directly with existing scripts.

`worker` means the step materializes as a delegated child task.

This layer now supports two honest worker policies:

- controlled worker step: delegate, launch the real controlled Codex run, finalize the worker result, then continue local steps
- manual-controlled worker step: delegate, prepare handoff and ticket, and leave the root waiting for a later worker result instead of pretending the chain already completed

## Planning

Use:

```text
./scripts/task_chain_plan.sh repo-analysis-worker "<title>"
./scripts/task_chain_plan.sh repo-analysis-worker-manual "<title>"
./scripts/task_chain_plan.sh repo-analysis-worker-manual-multi "<title>"
```

This creates a root `task-chain` task in `planned` chain state and writes a v2 `chain_plan`.

The controlled default plan is:

1. local self-check
2. delegated repo analysis with real Codex run
3. local comparison artifact after the worker step

The third step is intentionally non-critical so the chain can express warning-grade completion instead of only binary success/failure.

The manual-controlled plan is:

1. local self-check
2. delegated repo analysis with `await_worker_result: true`
3. local comparison artifact after the worker result is registered

That plan intentionally stops after step 2 with the root in `status: delegated` + `chain_status: awaiting_worker_result` until the worker result is registered.

The multi-await manual plan is:

1. local self-check
2. delegated repo analysis architecture with `await_worker_result: true`
3. delegated repo analysis verification with `await_worker_result: true`
4. one local architecture summary behind the `architecture-ready` barrier
5. one local comparison artifact behind the `analysis-workers` barrier

That plan intentionally stops after delegating both workers with the root in `status: delegated` + `chain_status: awaiting_worker_result` while at least one awaited worker result is still missing.

Current explicit barriers for that plan:

- `architecture-ready`: depends only on `delegated-repo-analysis-architecture`
- `analysis-workers`: depends on both awaited worker steps and is also the visible await group for them

## Running

Use:

```text
./scripts/task_chain_run_v2.sh repo-analysis-worker "<title>"
./scripts/task_chain_run_v2.sh repo-analysis-worker-manual "<title>"
./scripts/task_chain_run_v2.sh repo-analysis-worker-manual-multi "<title>"
```

For `repo-analysis-worker`, the runner:

1. creates the v2 plan
2. marks the root as running
3. executes the local step
4. creates and delegates a child `repo-analysis` task
5. launches the real Codex run for that child
6. finalizes the worker result
7. executes the trailing local step
8. collects mixed chain results into a root-level snapshot
9. finalizes the root chain with an aggregated artifact

For `repo-analysis-worker-manual`, the runner:

1. creates the v2 plan
2. marks the root as running
3. executes the local step
4. creates and delegates a child `repo-analysis` task
5. prepares handoff packet and Codex ticket
6. finalizes the root as `delegated` / `awaiting_worker_result`

For `repo-analysis-worker-manual-multi`, the runner:

1. creates the v2 plan
2. marks the root as running
3. executes the local step
4. creates and delegates every planned `await_worker_result` worker child
5. prepares handoff packet and Codex ticket for each delegated worker child
6. finalizes the root as `delegated` / `awaiting_worker_result`

Resume the same root later with:

```text
./scripts/task_chain_resume.sh <root_task_id>
```

That resume flow:

1. verifies the root is still `delegated` / `awaiting_worker_result`
2. scans every worker step marked `await_worker_result`
3. updates each resolved worker step to `done` / `failed` / `blocked` once its child result exists
4. computes each declared dependency barrier as `satisfied`, `waiting`, `blocked`, or `failed`
5. keeps the root delegated if one or more awaited worker results are still absent and no critical worker has already forced closure
6. runs only the planned local steps whose barrier is already `satisfied`
7. skips planned local steps when their barrier is already `failed` or `blocked`
8. finalizes the root with the same collector/finalizer used elsewhere

Minimal continuation policy for multi-await roots:

- a planned step can run only when its explicit barrier is `satisfied`
- a barrier becomes `waiting` while one or more dependency steps are still `delegated`, `running`, or `planned`
- a barrier becomes `failed` when one of its dependency steps is `failed` or `skipped`
- a barrier becomes `blocked` when one of its dependency steps is `blocked`
- continuation after only a subset of workers is now modeled by a smaller explicit barrier, not by guessing from step position
- a critical worker outcome of `failed` or `blocked` can close the root immediately even if another awaited worker is still unresolved
- if one worker is already `done` and another still waits, the root remains `awaiting_worker_result` unless an independent local step is now fully unblocked by its own barrier

For lower-friction operations, the recommended wrapper is now:

```text
./scripts/task_chain_settle.sh <root_task_id|worker_task_id> [<done|failed|blocked> "<summary>" [--artifact <path> ...]]
```

That settlement flow can:

1. accept the root or the delegated worker child
2. register the worker result when the operator already has it in hand
3. reconcile one or more already-resolved awaited worker children
4. detect whether the root still needs to wait for other workers
5. trigger `task_chain_resume.sh` automatically when reconciliation work exists
6. leave a `chain-settlement` trace on the root

When the worker result arrives as a canonical packet instead of a manual shell call, the recommended entry point is:

```text
./scripts/task_import_worker_result.sh <packet_path> --settle
```

That import flow:

1. validates the packet against the current canonical worker-result protocol
2. validates the delegated child task and optional root reference
3. records the worker result through the existing task lifecycle
4. optionally triggers settlement immediately

Canonical packet protocol:

```text
protocols/WORKER_RESULT_PACKET.md
protocols/examples/worker_result_packet.example.json
```

The outbound worker leg now has a symmetric machine-readable packet too:

```text
protocols/WORKER_HANDOFF_PACKET.md
protocols/examples/worker_handoff_packet.example.json
./scripts/task_export_worker_handoff.sh <task_id>
```

That packet complements the existing:

- `handoffs/<task_id>.md`
- `handoffs/<task_id>.codex.md`

instead of replacing the human-readable delegation lane.

For an end-to-end protocol verification of the manual-controlled roundtrip, use:

```text
./scripts/verify_worker_packet_roundtrip.sh
```

That verify covers:

1. automatic outbound handoff packet export
2. canonical inbound worker result packet import
3. settlement/resume of the delegated root
4. both success and blocked paths

The official capability matrix now registers that flow as:

```text
worker packet roundtrip
```

inside the deep verification lane driven by:

```text
./scripts/verify_capability_matrix.sh
```

This keeps the normal `self-check` lightweight while still making the worker roundtrip visible as an official repository capability.

Current policy:

- multi-await settlement/resume now supports more than one `await_worker_result` worker step per root
- local continuation stays intentionally simple: only steps whose explicit barrier is `satisfied` can run after reconciliation
- dependency groups are visible in `chain_plan`, `chain_summary`, reconcile output, and the final artifact
- unsupported local step task types in resume still fail explicitly instead of inventing an execution path

For a broader operational sweep across delegated roots, use:

```text
./scripts/task_chain_reconcile_pending.sh
./scripts/task_chain_reconcile_pending.sh --apply
```

This sweep:

1. scans manual-controlled roots with `await_worker_result`
2. shows all awaited worker children per root, including which ones are already ready and which ones still wait
3. classifies each root as `still_waiting`, `ready_for_settlement`, or `already_reconciled`
3. keeps inspect mode read-only
4. uses `task_chain_settle.sh` in apply mode instead of inventing a parallel reconcile path

For a reproducible verify of the new multi-await behavior, use:

```text
./scripts/verify_multi_worker_await_roundtrip.sh
```

That verify covers:

1. one worker resolved while another still waits
2. a local step behind `architecture-ready` runs while `analysis-workers` still waits
3. both workers resolved so the full barrier can open and the root can continue and close
4. one critical worker blocks `analysis-workers` after the narrower barrier already succeeded

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
- dependency barrier counts and per-barrier status
- `worker_steps_done`
- `worker_steps_delegated`
- `worker_steps_running`
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
- any worker step with `await_worker_result: true` keeps the root delegated until the worker result exists
- once that worker result is registered, `./scripts/task_chain_resume.sh` is the explicit bridge that moves the root forward again
- `./scripts/task_chain_settle.sh` is the shorter operational wrapper around that bridge
- a manual-controlled worker result may close as `done`, `failed`, or `blocked`
- `done` resumes the trailing local step when one exists
- `failed` or `blocked` on a critical worker step closes the root as `failed` or `blocked`
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
