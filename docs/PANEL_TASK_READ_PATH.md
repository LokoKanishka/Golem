# Panel Task Read Path

This document defines the current read-only path between the panel side of Golem and the canonical task inventory in repo.

## Source of truth

The panel-side read path now reads directly from:

```text
tasks/task-*.json
```

That inventory is the canonical repo-governed task truth.

This phase does not authorize panel mutations.

## Adapter

The immediate backend adapter is:

```text
./scripts/task_panel_read.sh
```

Supported commands:

- `./scripts/task_panel_read.sh list [--status <status>] [--limit <n>]`
- `./scripts/task_panel_read.sh show <task-id|path>`
- `./scripts/task_panel_read.sh summary`

All commands emit JSON and declare:

- `source_of_truth: tasks/*.json`
- `canonical_only: true`

## Capabilities exposed

### List

Returns a compact task list suitable for panel tables or inventory views.

Each item includes at least:

- `id`
- `title`
- `status`
- `type`
- `owner`
- `source_channel`
- `created_at`
- `updated_at`
- `delivery_state`

### Show

Returns the full canonical task JSON for a single task, wrapped with read-path metadata.

### Summary

Returns a minimal inventory summary with:

- `total`
- `status_counts`
- `latest_updated_at`
- `top_owners`

## Canonical-only rule

This adapter must not read legacy task representations or stale panel snapshots as task truth.

If a requested task file is not canonical, the adapter fails instead of silently downgrading to a legacy interpretation.

## Explicitly out of scope

This phase does not include:

- create from panel
- update from panel
- close from panel
- WhatsApp task commands
- automatic reconciliation events
