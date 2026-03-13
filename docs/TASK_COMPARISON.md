# Task Comparison

This document defines the formal task wrapper for Golem's simple file comparison capability.

## Goal

Run the existing comparison capability as a task so Golem keeps:

- task creation
- status transitions
- persisted command output
- recorded comparison artifact paths
- final closure as `done` or `failed`

## Script

The entry point is:

```text
./scripts/task_run_compare.sh files "<title>" <slug> <file_a> <file_b>
```

## Input

The runner expects:

- a human title for the task
- a slug for the comparison artifact
- two existing text or markdown files inside the repo

Internally it calls:

```text
./scripts/browser_compare.sh files <slug> <file_a> <file_b>
```

## Persisted task data

The runner appends an object to `outputs` with fields such as:

- `kind`
- `captured_at`
- `command`
- `mode`
- `slug`
- `input_a`
- `input_b`
- `exit_code`
- `content`

On success it appends an object to `artifacts` with:

- `path`
- `kind`
- `created_at`

It also refreshes `updated_at` and appends a short note to `notes`.

## Artifact

The generated artifact is the markdown comparison report produced by `browser_compare.sh` under `outbox/manual/`.

## Success and failure

The runner marks the task:

- `done` when `browser_compare.sh` exits successfully and prints `COMPARISON_OK <ruta>`
- `failed` when the command fails or when no valid comparison artifact path is produced

## Safety

- works only inside the repo task store
- does not touch `~/.openclaw`
- does not modify live gateway configuration
- does not add `outbox/manual/` files to git
- uses temporary files and atomic replacement for task JSON updates
