# Task Artifact

This document defines the first formal task wrapper for Golem's simple artifact capability.

## Goal

Run simple artifact generation under the task model so Golem keeps:

- task creation
- status transitions
- persisted command output
- recorded artifact paths
- final closure as `done` or `failed`

## Script

The entry point is:

```text
./scripts/task_run_artifact.sh snapshot "<title>" <slug>
./scripts/task_run_artifact.sh find "<title>" <slug> <texto>
```

## Task types

The runner creates one of these task types:

- `artifact-snapshot`
- `artifact-find`

## Flow

The runner performs these steps:

1. creates a new task
2. updates it to `running`
3. runs `./scripts/browser_artifact.sh` in the requested mode
4. persists the output in the task JSON
5. records the generated file in `artifacts`
6. closes the task as `done` or `failed`

## Browser profile selection

The artifact runner uses stable existing browser profiles only.

- if `GOLEM_BROWSER_PROFILE` is set, it uses that profile only
- otherwise it tries `chrome` first
- if `chrome` is not usable for the artifact run, it retries with `openclaw`

This keeps the task flow robust without changing live gateway configuration.

## Persisted data

The runner appends an object to `outputs` with fields such as:

- `kind`
- `captured_at`
- `command`
- `mode`
- `slug`
- `query` when applicable
- `exit_code`
- `profile`
- `content`
- `attempts`

On success it appends an object to `artifacts` with:

- `path`
- `kind`
- `created_at`

It also refreshes `updated_at` and appends a short note to `notes`.

## Final state rules

The runner marks the task:

- `done` when `browser_artifact.sh` returns success and prints `ARTIFACT_OK <ruta>`
- `failed` when every attempted profile fails or when no valid artifact path is produced

## Safety

- works only inside the repo task store
- does not touch `~/.openclaw`
- does not modify live gateway configuration
- does not add `outbox/manual/` files to git
- uses temporary files and atomic replacement for task JSON updates
