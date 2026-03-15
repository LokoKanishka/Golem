# Task Orchestration Conditional

This document defines the first conditional orchestration layer for Golem chains.

## Goal

Allow the root of a mixed chain to make one honest next-step decision after a real worker step instead of only summarizing the worker result afterward.

This is intentionally small:

- one worker outcome source
- one conditional decision
- one optional follow-up local step
- explicit skipped-step evidence

It is not a workflow engine.

## Conditional Chain Type

The first v3 conditional chain type is:

```text
repo-analysis-worker-conditional
```

Its default flow is:

1. `local-self-check`
2. `delegated-repo-analysis`
3. `conditional-decision`
4. `local-review-worker-outcome`

The last step only runs when the worker result closes with:

```text
worker_result_status=done
```

If the worker closes as `failed`, the root records the decision, marks the local follow-up as `skipped`, and closes with a coherent failed chain result.

## Decision Script

Use:

```text
./scripts/task_chain_decide_next.sh <root_task_id>
```

The decision layer reads:

- the current `chain_plan`
- collected worker outcomes
- `worker_result_status` from the delegated step

It persists on the root:

- `decision_reason`
- `decision_source_step`
- `decision_source_worker_result_status`
- `next_step_selected`
- `skipped_steps`
- `conditional_outcomes`

## Runner

Use:

```text
./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "<title>"
```

The runner:

1. creates a v3 conditional root plan
2. executes the local self-check
3. launches a real delegated worker child
4. finalizes the worker result
5. runs the conditional decision
6. either executes or skips the final local review step
7. finalizes the root with the aggregated artifact

## Controlled Failover Variant

For verification and controlled failover testing, the runner also supports:

```text
./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "<title>" --force-worker-result failed
```

This still performs the real worker run, but closes the worker result as `failed` so the chain can prove:

- the decision path is exercised
- the follow-up local step is skipped
- the root closes honestly with failure semantics

## What Persists at the Root

The root `chain_summary` should include at least:

- `decision_reason`
- `decision_source_step`
- `next_step_selected`
- `skipped_steps`
- `conditional_outcomes`

The final artifact should also expose those fields in a dedicated conditional section.

## Honest Scope

This layer does not add:

- arbitrary branching graphs
- retries
- loops
- scheduling
- parallel branches

It only lets the root make one explicit post-worker decision and preserve the evidence of that choice.
