# Codex Controlled Run

This document defines the first controlled Codex CLI execution flow for delegated Golem tasks.

## What "controlled run" means

A controlled run means:

1. a delegated task already exists
2. Golem ensures the Codex ticket exists
3. Golem launches `codex exec` explicitly
4. the run leaves auditable evidence in the repo
5. a human or wrapper script still decides how to close the task

This is not background automation.

## What changes compared to the previous manual loop

Before this step, Golem only prepared:

- task
- delegated state
- handoff packet
- Codex-ready ticket

Now Golem can also:

- mark the task as `worker_running`
- validate policy and preconditions before launch
- run Codex CLI over the prepared ticket
- persist prompt, log, and final message as runtime-only files

## What remains manual

This version still keeps explicit closure.

After the controlled run finishes, an operator can still call:

```text
./scripts/task_finish_codex_run.sh <task_id> <status> "<summary>" [--artifact <path> ...]
```

Or use the lower-friction wrapper:

```text
./scripts/task_finalize_codex_run.sh <task_id> <done|failed>
```

That means:

- no scheduler
- no background daemon
- no callback integration
- no silent auto-close

## Worker-related task semantics

The delegated execution flow is now:

- `delegated`
- `worker_running`
- `done` or `failed`

`worker_running` means:

- the task was already delegated
- a Codex run was explicitly started
- the run has a prompt/ticket/log trail
- the task has not been formally closed yet

The richer internal worker states live in `worker_run.state`:

- `ready`
- `running`
- `finished`
- `failed`

## How to start a controlled run

Use:

```text
./scripts/task_start_codex_run.sh <task_id>
```

The script:

1. runs preflight
2. checks policy permission
3. ensures `handoffs/<task_id>.codex.md` exists
4. writes a controlled prompt file
5. marks the worker as `ready`, then `running`
6. runs Codex CLI in the allowed sandbox mode
7. persists:
   - prompt path
   - ticket path
   - log path
   - last message path
   - command
   - exit code

If `codex exec` exits non-zero, the task is marked failed immediately and the worker state becomes `failed`.

## How to close the run

Use:

```text
./scripts/task_finish_codex_run.sh <task_id> <status> "<summary>" [--artifact <path> ...]
```

The script:

- accepts `worker_running` as the normal pre-close state
- can also accept `delegated` for a documented fallback
- reuses the automatic worker result extraction when no result artifact was passed
- reuses `task_record_worker_result.sh`

If the run finished technically well, `task_finish_codex_run.sh` records the semantic final result and persists `worker_run.result_status`.

`task_finalize_codex_run.sh` goes one step further:

- extracts a normalized result artifact from `run.last.md` and/or the log
- derives a minimal summary
- records the `worker-result`
- closes the task with less manual writing

## Where the evidence lives

The controlled run now splits durable local evidence from runtime-only files.

Durable local evidence under `handoffs/`:

- `handoffs/<task_id>.codex.md`
- `handoffs/<task_id>.run.result.md` after extraction/finalization

Runtime-only files also under `handoffs/`:

- `handoffs/<task_id>.run.prompt.md`
- `handoffs/<task_id>.run.log`
- `handoffs/<task_id>.run.last.md`

The runtime-only files are intentionally excluded from Git by default.

They are useful for:

- short-lived debugging
- local audit while the run is fresh
- extraction of the normalized result artifact

But they are not treated as durable repository evidence once `run.result.md` exists.

## How to audit the run

The core audit points are:

- the exact ticket file used
- the generated controlled prompt
- the Codex CLI command recorded in the task
- the run log
- the last message file
- the final worker result recorded in the task

Useful commands:

```text
./scripts/task_worker_run_show.sh <task_id>
./scripts/task_worker_summary.sh <task_id>
sed -n '1,220p' handoffs/<task_id>.run.log
```

## Why this is not full automation yet

This layer improves execution traceability, but it still does not provide:

- automatic retries
- job queueing
- callback-based closure
- async worker management
- autonomous commit/push behavior

It is an explicit, audited bridge between preparation and execution.
