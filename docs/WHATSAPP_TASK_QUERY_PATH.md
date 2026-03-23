# WhatsApp Task Query Path

This document defines the current minimal WhatsApp query path over the canonical task lane.

## Scope

This phase is query-only.

It supports:

- summary
- list
- show

It does not support:

- create
- update
- close

## Path

The current repo-local bridge is:

```text
./scripts/task_whatsapp_query.py
```

That bridge does not read task files directly.

It queries the local HTTP API:

```text
./scripts/task_panel_http_server.py
```

which in turn delegates to:

- `./scripts/task_panel_read.sh`
- `tasks/task-*.json`

## Supported query shapes

Structured:

- `./scripts/task_whatsapp_query.py summary`
- `./scripts/task_whatsapp_query.py list --limit 5`
- `./scripts/task_whatsapp_query.py show <task-id>`

WhatsApp-like text:

- `./scripts/task_whatsapp_query.py --text "tasks summary"`
- `./scripts/task_whatsapp_query.py --text "tasks list limit 5"`
- `./scripts/task_whatsapp_query.py --text "task show <task-id>"`

## Formatting

Responses are intentionally short and channel-friendly:

- `TASKS SUMMARY`
- `TASKS LIST`
- `TASK DETAIL`

No task mutation is attempted in this phase.

## Explicitly out of scope

This phase does not include:

- WhatsApp task mutations
- delivery proof changes
- provider reconciliation
- auth or remote exposure
