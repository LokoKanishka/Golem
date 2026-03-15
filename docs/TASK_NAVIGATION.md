# Task Navigation

This document defines the formal task wrapper for Golem's minimal navigation capability.

## Goal

Run navigation operations as tasks so Golem keeps:

- task creation
- transition to `running`
- persisted navigation output
- final closure as `done`, `blocked`, or `failed`

## Script

The entry point is:

```text
./scripts/task_run_nav.sh tabs "<title>"
./scripts/task_run_nav.sh open "<title>" <url>
./scripts/task_run_nav.sh snapshot "<title>"
```

## Supported modes

- `tabs`
- `open`
- `snapshot`

## What the runner does

The runner:

1. creates a task of type `nav-tabs`, `nav-open`, or `nav-snapshot`
2. runs a browser readiness gate first
3. if readiness passes, moves the task to `running`
4. runs `./scripts/browser_nav.sh`
5. persists the result in `outputs`
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
- `url` when applicable
- `attempts`

Navigation does not create artifacts in this stage.

## Success and failure

The task is marked:

- `done` when a navigation attempt finishes with exit code `0`
- `blocked` when browser readiness detects that no usable browser target exists before execution
- `failed` when readiness passed but navigation still fails for an internal or runtime reason

When the runner closes as `blocked`, it keeps the readiness evidence in `outputs.browser_readiness` and uses `exit_code: 2` as the machine-readable convention for operational blocking.
