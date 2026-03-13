# Worker Run Governance

This document defines the first governance layer for real Codex runs launched from Golem.

## What this layer governs

This layer governs four things:

- whether a task type may launch a real Codex run
- whether the task satisfies preconditions before launch
- how the worker run state is persisted
- what happens when `codex exec` finishes successfully or fails technically

## Main distinction in the delegated flow

These are different steps:

1. delegate a task
2. prepare handoff and Codex ticket
3. decide whether a real Codex run is allowed
4. run preflight
5. launch Codex
6. close the worker result

Golem now treats those as separate concerns on purpose.

## What the policy decides

`config/worker_run_policy.json` decides whether a task type can launch a real Codex CLI run in this stage.

In this version:

- `repo-analysis` is allowed
- `bibliography-build` is allowed
- other task types are denied by default unless the policy changes

## What preflight validates

`./scripts/task_worker_preflight.sh <task_id>` validates at least:

- task existence
- current task status
- task is not already closed
- worker is not already running
- handoff presence
- ticket presence or generation
- repo existence
- Codex CLI availability
- policy permission

## Worker run states

The task still uses normal global task states such as:

- `delegated`
- `worker_running`
- `done`
- `failed`

But the richer worker semantics live in `worker_run.state`:

- `ready`
- `running`
- `finished`
- `failed`

Typical meaning:

- `ready`: preflight and policy passed, launch is about to happen
- `running`: Codex CLI is currently executing
- `finished`: Codex CLI ended with `exit_code = 0`
- `failed`: Codex CLI ended with non-zero exit or the run became invalid

The task may also persist:

- `worker_run.result_status`
- `worker_run.sandbox_mode`
- `worker_run.decision_source`
- `worker_run.policy_version`

## What happens if `codex exec` fails

If `codex exec` exits non-zero:

- `worker_run.state` becomes `failed`
- the task records run-failure evidence
- the task global status becomes `failed`
- the task is not left in ambiguous `worker_running`

That makes the technical failure explicit even without full automation.

## What remains manual

If `codex exec` finishes technically well:

- Golem leaves the task in `worker_running`
- `worker_run.state` becomes `finished`
- the operator still calls `task_finish_codex_run.sh`

This keeps the semantic closure explicit:

- what the run technically did
- what result we accept as final

## Why this is not a daemon

This layer still does not provide:

- background orchestration
- queue management
- callbacks
- retries
- scheduling

It only makes the existing controlled run auditable, policy-driven, and less ambiguous.
