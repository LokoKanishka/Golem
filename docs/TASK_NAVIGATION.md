# Task Navigation

This document defines the formal task wrapper for Golem's minimal navigation capability.

## Goal

Run navigation operations as tasks so Golem keeps:

- task creation
- transition to `running`
- persisted navigation output
- final closure as `done` or `failed`

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
2. moves it to `running`
3. runs `./scripts/browser_nav.sh`
4. persists the result in `outputs`
5. closes the task as `done` or `failed`

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
- `failed` when all attempted profiles fail, including relay or tab errors
