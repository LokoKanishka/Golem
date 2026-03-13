# Task Reading

This document defines the formal task wrapper for Golem's precise reading capability.

## Goal

Run reading operations as tasks so Golem keeps:

- task creation
- transition to `running`
- persisted textual output
- final closure as `done` or `failed`

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
2. moves it to `running`
3. runs `./scripts/browser_read.sh`
4. persists the textual result in `outputs`
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
- `query` when applicable
- `attempts`

## Success and failure

The task is marked:

- `done` when a reading attempt finishes with exit code `0`
- `failed` when all attempted profiles fail, including no-tabs or relay errors

Reading does not generate artifacts in this stage.
