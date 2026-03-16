# Task Self-Check

This document defines the first live task flow built on top of Golem's local task model.

## Goal

Run `self-check` as a formal task with:

- task creation
- status transition to `running`
- persisted output
- final task closure as `done` or `failed`

## Script

The entry point is:

```text
./scripts/task_run_self_check.sh "<title>"
```

This runner is intentionally the fast operational lane.

It does not execute deep capability verifies such as the canonical worker roundtrip packet flow.

For the official deep verification sweep, use:

```text
./scripts/verify_capability_matrix.sh
```

and inspect the `worker packet roundtrip` capability there.

For the higher-level operational view that aggregates this fast lane with browser and worker subsystem verifies, use:

```text
./scripts/verify_system_readiness.sh
```

For the short live demo-state that reuses this fast lane together with the real stack, worker stack, browser stack, and generated smoke evidence, use:

```text
./scripts/verify_live_smoke_profile.sh
```

## Flow

The runner performs these steps:

1. creates a new task of type `self-check`
2. updates the task to `running`
3. runs `./scripts/self_check.sh`
4. persists the textual result inside the task JSON
5. updates the task to a final state

## Final states

The runner marks the task:

- `done` when `./scripts/self_check.sh` exits zero and `estado_general` is not `FAIL`
- `failed` when the command exits non-zero or when `estado_general: FAIL`

## Persisted data

The self-check result is appended to `outputs` as a structured object containing:

- `kind`
- `captured_at`
- `command`
- `exit_code`
- `estado_general`
- `content`

The runner also appends a short note to `notes` and refreshes `updated_at`.

## Safety

- works only inside the repo task store
- does not touch `~/.openclaw`
- does not modify live gateway configuration
- uses temporary files plus atomic replace for the final JSON write
- if the runner aborts unexpectedly after creating the task, it makes a best effort to leave the task as `failed`
