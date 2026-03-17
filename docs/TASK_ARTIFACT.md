# Task Artifact

This document defines the first formal task wrapper for Golem's simple artifact capability.

## Goal

Run simple artifact generation under the task model so Golem keeps:

- task creation
- status transitions
- persisted command output
- recorded artifact paths
- final closure as `done`, `blocked`, or `failed`

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
2. runs a browser readiness gate first
3. if readiness passes, updates it to `running`
4. runs `./scripts/browser_artifact.sh` in the requested mode
5. persists the output in the task JSON
6. records the generated file in `artifacts` when one exists
7. closes the task as `done`, `blocked`, or `failed`

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

That artifact path is internal durable staging evidence only.

For a user-facing file claim such as "already on your desktop" or "already in downloads", the repo now requires a second lane:

- resolve the canonical visible destination with `./scripts/resolve_user_visible_destination.sh`
- materialize the staged artifact with `./scripts/task_materialize_visible_artifact.sh`
- verify `exists`, `readable`, `owner`, and `path_normalized` after delivery

Without that second verified lane, `outbox/manual/` does not count as a visible user-facing delivery.

If the artifact will later be used as a channel attachment or other downstream media, the repo now also supports a third lane:

- register canonical media identity with `./scripts/task_register_media_ingestion.sh`
- verify the stored material identity with `./scripts/task_verify_media_ready.sh`

That third lane persists `sha256`, `size`, `mime`, `owner`, and the canonical normalized path so the task can later prove which exact file was ingested.

It also refreshes `updated_at` and appends a short note to `notes`.

## Final state rules

The runner marks the task:

- `done` when `browser_artifact.sh` returns success and prints `ARTIFACT_OK <ruta>`
- `blocked` when browser readiness detects that no usable browser target exists before execution
- `failed` when readiness passed but no valid artifact path is produced or the artifact flow fails internally

When the task closes as `blocked`, the runner preserves `browser_readiness` evidence in `outputs` and uses `exit_code: 2` as the machine-readable blocked convention.

## Safety

- works only inside the repo task store
- does not touch `~/.openclaw`
- does not modify live gateway configuration
- does not add `outbox/manual/` files to git
- uses temporary files and atomic replacement for task JSON updates
