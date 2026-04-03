# Panel Task Read Path

This document defines the current read-only path between the panel side of Golem and the canonical task inventory in repo.

## Source of truth

The panel-side read path now reads directly from:

```text
tasks/task-*.json
```

That inventory is the canonical repo-governed task truth.

This adapter remains read-only.

Panel-side mutations now live in the separate path documented in `docs/PANEL_TASK_MUTATION_PATH.md`.

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
- `host_evidence_present`

When host evidence is already attached canonically to the task, list cards may also expose the latest host surface category/confidence for quick routing.

When a task declares a canonical host expectation, list cards may also expose whether that expectation exists and the latest verification status over the attached host evidence.

### Show

Returns the full canonical task JSON for a single task, wrapped with read-path metadata.

When the task already contains canonically attached host evidence, the show payload also exposes a computed `host_evidence_summary` so panel-side readers do not need to reconstruct host state manually from raw evidence, outputs and artifacts.

When the task declares a canonical host expectation, the show payload also exposes:

- `host_expectation`
- `host_verification`

That keeps the declarative task<->host loop visible on the same read path already used by panel and bridge callers.

### Summary

Returns a minimal inventory summary with:

- `total`
- `status_counts`
- `latest_updated_at`
- `top_owners`
- `host_evidence_tasks`
- `host_expectation_tasks`
- `host_verification_counts`

## Canonical-only rule

This adapter must not read legacy task representations or stale panel snapshots as task truth.

If a requested task file is not canonical, the adapter fails instead of silently downgrading to a legacy interpretation.

## Explicitly out of scope

This read adapter does not include:

- create from panel
- update from panel
- close from panel
- WhatsApp task commands
- automatic reconciliation events
