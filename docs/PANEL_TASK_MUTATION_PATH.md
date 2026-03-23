# Panel Task Mutation Path

This document defines the current minimal mutation path between the panel-side backend and the canonical task inventory in repo.

## Source of truth

Mutations operate directly on:

```text
tasks/task-*.json
```

The adapter does not introduce a second task model.

It delegates to the canonical scripts that already govern task mutation.

## Adapter

The immediate backend mutation adapter is:

```text
./scripts/task_panel_mutate.sh
```

Supported commands:

- `./scripts/task_panel_mutate.sh create --title <title> --objective <objective> [...]`
- `./scripts/task_panel_mutate.sh update <task-id|path> [...]`
- `./scripts/task_panel_mutate.sh close <task-id|path> --status <done|failed|blocked|canceled> --note <note> [...]`

All commands emit JSON and declare:

- `source_of_truth: tasks/*.json`
- `canonical_only: true`
- `panel_adapter: task_panel_mutate.sh`

## Delegation to canonical scripts

The adapter does not reimplement task creation, update, or closure semantics.

It delegates to:

- `./scripts/task_create.sh`
- `./scripts/task_update.sh`
- `./scripts/task_close.sh`

and then returns the resulting canonical task through the read-model exposed by `./scripts/task_panel_read.sh show`.

## Mutations supported in this phase

### Create

Supports at least:

- `title`
- `objective`
- `type`
- `owner`
- `source`
- `accept`
- `canonical-session`
- `origin`

Defaults are panel-oriented:

- `source=panel`
- `origin=panel`

### Update

Supports at least:

- `status`
- `owner`
- `title`
- `objective`
- `source`
- `append-accept`
- `note`
- `actor`

Defaults are panel-oriented:

- `source=panel`
- `actor=panel`

### Close

Supports:

- `status`
- `note`
- `actor`
- `owner`

Default actor:

- `actor=panel`

## Validations

The adapter relies on the validations already present in the canonical scripts.

That means:

- invalid status values fail in the canonical script layer;
- invalid source values fail in the canonical script layer;
- closure still requires an explicit note;
- the resulting task still has to remain strict-validatable in repo.

## Explicitly out of scope

This phase does not include:

- WhatsApp task commands
- automatic panel events
- background reconciliation loops
- HTTP service design for OpenClaw
