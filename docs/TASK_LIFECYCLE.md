# Task Lifecycle

This document defines the basic lifecycle of a Golem task and the shared scripts that operate on it.

Markdown file outputs should also follow the minimum conventions in `docs/OUTPUT_CONVENTIONS.md`.

User-facing delivery truth is now tracked separately from the technical lifecycle. See `docs/TASK_USER_DELIVERY.md`.

Host screenshot truth is also tracked separately from the technical lifecycle. See `docs/TASK_SCREENSHOT.md`.

The user-facing readiness profile sits one level above those specialized lanes and summarizes whether the current repo-local user-facing contract is really ready. See `docs/USER_FACING_READINESS.md`.

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

It also accepts optional step metadata:

```text
TASK_OBJECTIVE="..."
TASK_STEP_NAME="delegated-repo-analysis"
TASK_STEP_ORDER=2
TASK_CRITICAL=true
TASK_EXECUTION_MODE=worker
./scripts/task_new.sh <type> <title>
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

It may also inherit step-aware metadata through environment variables such as:

- `TASK_CHILD_OBJECTIVE`
- `TASK_CHILD_STEP_NAME`
- `TASK_CHILD_STEP_ORDER`
- `TASK_CHILD_CRITICAL`
- `TASK_CHILD_EXECUTION_MODE`
- `TASK_CHILD_DEPENDS_ON`

## Move to running

Tasks move to running with:

```text
./scripts/task_update.sh <task_id> running
```

That keeps the existing task model intact and refreshes `updated_at`.

Tasks can also move to `delegated` when they are prepared for a future worker handoff without executing any worker yet.

Delegated tasks can also move to `worker_running` when a controlled Codex CLI run starts.

Before a real Codex run starts, Golem can validate governance with:

```text
./scripts/task_worker_can_run.sh <task_id>
./scripts/task_worker_preflight.sh <task_id>
```

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

Closing a task as `done` still means technical completion only.

It does not automatically authorize a user-facing success claim such as "already delivered" or "the user can see it".

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
It can also close the task as `blocked` when the worker result is available but the outcome was prevented by an external or operational blocker.

When the returned artifact is Markdown, the script validates it before registering it.

Controlled Codex execution uses:

```text
./scripts/task_start_codex_run.sh <task_id>
./scripts/task_finish_codex_run.sh <task_id> <status> <summary> [--artifact <path> ...]
```

The start step moves the task into `worker_running` and persists run evidence.

If `codex exec` exits non-zero, the start step now marks the task coherently as failed and leaves worker evidence behind.

The finish step closes the loop coherently after the run has completed.

## Record user-facing delivery

The canonical delivery states are recorded separately from `status`:

```text
./scripts/task_record_delivery_transition.sh <task_id> <submitted|accepted|delivered|visible|verified_by_user> <actor> <channel> <evidence>
```

Each transition persists:

- `state`
- `timestamp`
- `actor`
- `channel`
- `evidence`

For a compact audit view, use:

```text
./scripts/task_delivery_summary.sh <task_id>
```

To guard a final user-facing success claim, use:

```text
./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]
```

That claim must not pass unless the task reached at least `visible`.

When the delivery claim also depends on a visible file result, resolve and verify that path explicitly:

```text
./scripts/resolve_user_visible_destination.sh <desktop|downloads> [filename] [--json]
./scripts/task_materialize_visible_artifact.sh <task_id> <artifact_path> <desktop|downloads> [filename] [--json]
```

That second lane persists canonical evidence for:

- `delivery_target`
- `resolved_path`
- `verified_at`
- `verification_result`
- `exists`
- `readable`
- `owner`
- `path_normalized`

When the claim depends on host-side visual evidence, use the screenshot lane explicitly:

```text
./scripts/resolve_host_screenshot_destination.sh <task_id> <target_kind> [output_hint] [--json]
./scripts/task_capture_host_screenshot.sh <task_id> <target_kind> <target_ref|-> <actor> <evidence> [output_hint] [--json]
./scripts/task_verify_host_screenshot.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
./scripts/task_screenshot_summary.sh <task_id>
```

That lane keeps `captured` separate from `verified` and blocks visual claims until the screenshot identity is verified.

If the file cannot be verified on a user-visible destination after materialization, the result must stay `BLOCKED` or `FAIL`, and the final user-facing claim must remain blocked.

When the user-facing channel is WhatsApp, persist that lane separately too:

```text
./scripts/task_record_whatsapp_delivery.sh <task_id> <requested|accepted_by_gateway|provider_delivery_unproved|delivered|verified_by_user> <actor> <provider> <to> <message_id|-> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>] [--evidence-kind <kind>] [--provider-status <status>] [--provider-reason <reason>] [--normalized-evidence-json <json>]
./scripts/task_record_whatsapp_provider_delivery.sh <task_id> <actor> <provider> <to> <message_id> <ambiguous|delivered|verified_by_user> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>] [--provider-status <status>] [--reason <reason>] [--normalized-evidence-json <json>]
./scripts/task_claim_whatsapp_delivery.sh <task_id> <actor> <requested_claim_level> <evidence> [claim_text]
```

That lane does not replace the generic `delivery_state`. It narrows the authorized wording for channel-specific claims.

For WhatsApp-required tasks:

- gateway acceptance is not the same as delivery
- provider ambiguity must stay conservative
- generic final success stays blocked until the WhatsApp lane reaches at least `delivered`

When the task also depends on canonical media identity, persist that lane separately too:

```text
./scripts/task_register_media_ingestion.sh <task_id> <task-artifact|visible-artifact|local-path> <source_ref> <actor> <evidence> [--json]
./scripts/task_verify_media_ready.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
./scripts/task_media_summary.sh <task_id>
```

That lane does not replace task `artifacts`. It proves whether a later delivery step is still referring to the exact same file material identity.

For media-required tasks:

- registration alone is not enough
- the final user-facing claim stays blocked until the media lane reaches `verified`
- missing paths, unreadable files, directories, and identity drift must remain visible as `blocked` or `failed`

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
./scripts/task_chain_status.sh <task_id>
```

## Plan and run a stronger mixed chain

The stronger orchestration flow now uses:

```text
./scripts/task_chain_plan.sh repo-analysis-worker "<title>"
./scripts/task_chain_run_v2.sh repo-analysis-worker "<title>"
```

That flow keeps the root in sync with:

- a planned step list
- local plus worker execution modes
- critical semantics
- final aggregated closure data

## Why this reduces duplication

Before this layer, each `task_run_*` script had to rewrite task JSON directly to:

- append outputs
- append artifacts
- close the task
- add notes

Now runners can focus on their real work and delegate lifecycle persistence to shared scripts. That keeps future capability runners simpler and makes the task layer a clearer base for later worker integration.

The same layer now supports a clean bridge toward future workers: tasks remain local JSON records, but they can expose a machine-readable handoff contract before any real worker integration exists.

That bridge now also supports manual return: a delegated task can receive a formal worker result and move back into a normal closed state without any automatic callback integration.
