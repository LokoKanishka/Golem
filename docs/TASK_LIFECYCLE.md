# Task Lifecycle

This document defines the basic lifecycle of a Golem task and the shared scripts that operate on it.

Markdown file outputs should also follow the minimum conventions in `docs/OUTPUT_CONVENTIONS.md`.

## Basic lifecycle

The minimal task flow is:

1. create the task
2. optionally relate it to a parent task or declare dependencies
3. move it to `running`
4. append outputs as work happens
5. register artifacts when files are produced
6. either close the task as `done`, `failed`, or `cancelled`, or delegate it for future worker execution
7. inspect a short summary when needed

## Create

New tasks are created with:

```text
./scripts/task_new.sh <type> <title>
```

This initializes the JSON file under `tasks/` with status `queued`.

For orchestration-aware creation, `task_new.sh` also accepts:

```text
TASK_PARENT_TASK_ID=<task_id_padre>
TASK_DEPENDS_ON='["task-a","task-b"]' ./scripts/task_new.sh <type> <title>
```

These fields are declarative only in this version. They do not schedule or block execution by themselves.

## Spawn child task

Direct child creation is available through:

```text
./scripts/task_spawn_child.sh <parent_task_id> <type> <title>
```

This creates a new task with:

- `parent_task_id` set to the parent
- `depends_on` initialized with the parent task id

## Move to running

Tasks move to running with:

```text
./scripts/task_update.sh <task_id> running
```

That keeps the existing task model intact and refreshes `updated_at`.

Tasks can also move to `delegated` when they are prepared for a future worker handoff without executing any worker yet.

## Add outputs

Runners persist outputs with:

```text
./scripts/task_add_output.sh <task_id> <kind> <exit_code> <content>
```

Base fields are:

- `kind`
- `captured_at`
- `exit_code`
- `content`

If a runner needs more metadata, it can pass `TASK_OUTPUT_EXTRA_JSON` as an object with extra fields such as command, mode, profile, inputs, or attempts.

## Add artifacts

Runners register generated files with:

```text
./scripts/task_add_artifact.sh <task_id> <kind> <path>
```

Base fields are:

- `path`
- `kind`
- `created_at`

If needed, runners can add metadata through `TASK_ARTIFACT_EXTRA_JSON`.

If an artifact is Markdown, it should be readable, timestamped, and non-trivial. The minimum validation is:

```text
./scripts/validate_markdown_artifact.sh <path>
```

## Close

Tasks are closed with:

```text
./scripts/task_close.sh <task_id> <status> [note]
```

Allowed closing statuses are:

- `done`
- `failed`
- `cancelled`

If a note is provided, it is appended to `notes`.

Chain root tasks may also persist a more expressive internal orchestration state in `chain_status` without changing the global lifecycle states.

## Delegate for future worker

Prepared-but-not-executed worker handoff uses:

```text
./scripts/task_delegate.sh <task_id>
```

This does not run any external worker. It persists a `handoff` block inside the task, appends a note, and moves the task to `delegated` when policy allows it.

The handoff block can be inspected with:

```text
./scripts/task_handoff_show.sh <task_id>
```

## Record manual worker result

Delegated tasks can be closed manually after Codex work returns:

```text
./scripts/task_record_worker_result.sh <task_id> <status> <summary> [--artifact <path> ...]
```

This appends a `worker-result` entry to `outputs`, optionally registers returned artifacts, and closes the task as `done` or `failed`.

When the returned artifact is Markdown, the script validates it before registering it.

## Summary

Short inspection is available through:

```text
./scripts/task_summary.sh <task_id>
```

It prints:

- task id
- type
- status
- title
- parent task id
- dependency count
- output count
- artifact count
- last note

Chain-specific inspection is also available through:

```text
./scripts/task_chain_summary.sh <task_id>
```

## Why this reduces duplication

Before this layer, each `task_run_*` script had to rewrite task JSON directly to:

- append outputs
- append artifacts
- close the task
- add notes

Now runners can focus on their real work and delegate lifecycle persistence to shared scripts. That keeps future capability runners simpler and makes the task layer a clearer base for later worker integration.

The same layer now supports a clean bridge toward future workers: tasks remain local JSON records, but they can expose a machine-readable handoff contract before any real worker integration exists.

That bridge now also supports manual return: a delegated task can receive a formal worker result and move back into a normal closed state without any automatic callback integration.
