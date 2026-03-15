# Task Reading

This document defines the formal task wrapper for Golem's precise reading capability.

## Goal

Run reading operations as tasks so Golem keeps:

- task creation
- transition to `running`
- persisted textual output
- final closure as `done`, `blocked`, or `failed`

## Script

The entry point is:

```text
./scripts/task_run_read.sh find "<title>" <texto>
./scripts/task_run_read.sh snapshot "<title>"
```

## Supported modes

- `find`
- `snapshot`

## What the runner does

The runner:

1. creates a task of type `read-find` or `read-snapshot`
2. runs a browser readiness gate first
3. if readiness passes, moves it to `running`
4. runs `./scripts/browser_read.sh`
5. persists the textual result in `outputs`
6. closes the task as `done`, `blocked`, or `failed`

## Persisted data

Each run appends an entry to `outputs` with fields such as:

- `kind`
- `captured_at`
- `exit_code`
- `content`
- `command`
- `mode`
- `profile`
- `query` when applicable
- `attempts`

## Success and failure

The task is marked:

- `done` when a reading attempt finishes with exit code `0`
- `blocked` when browser readiness proves that no usable browser target exists before execution
- `failed` when readiness passed but the reading flow still fails for an internal or runtime reason

Reading does not generate artifacts in this stage.

## Diagnostic note

If readiness blocks execution, the runner persists `browser_readiness` evidence and uses `exit_code: 2` as the machine-readable blocked convention. Use `./scripts/verify_browser_stack.sh` to distinguish `BLOCKED` from a real script `FAIL`.
