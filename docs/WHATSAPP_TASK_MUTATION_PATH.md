# WhatsApp Task Mutation Path

This document defines the current minimal WhatsApp mutation path over the canonical task lane.

## Scope

This phase supports:

- create
- update
- close

It does not support:

- delivery proof changes
- provider reconciliation
- auth or remote exposure

## Path

The current repo-local bridge is:

```text
./scripts/task_whatsapp_mutate.py
```

That bridge does not mutate task files directly.

It posts only to the local HTTP API:

```text
./scripts/task_panel_http_server.py
```

which in turn delegates to:

- `./scripts/task_panel_mutate.sh`
- `./scripts/task_create.sh`
- `./scripts/task_update.sh`
- `./scripts/task_close.sh`
- `tasks/task-*.json`

## Supported mutation shapes

Structured:

- `./scripts/task_whatsapp_mutate.py create --title "X" --objective "Y"`
- `./scripts/task_whatsapp_mutate.py update <task-id> --status running --note "..." --owner whatsapp-operator`
- `./scripts/task_whatsapp_mutate.py close <task-id> --status done --note "..."`

WhatsApp-like text:

- `./scripts/task_whatsapp_mutate.py --text "task create title=Title ; objective=Objective ; owner=whatsapp-operator"`
- `./scripts/task_whatsapp_mutate.py --text "task update <task-id> status=running ; note=working ; owner=whatsapp-operator"`
- `./scripts/task_whatsapp_mutate.py --text "task close <task-id> status=done ; note=finished ; owner=whatsapp-operator"`

Repeated fields:

- `accept=...` may be repeated on create
- `append_accept=...` may be repeated on update

## Formatting

Responses are intentionally short and channel-friendly:

- `TASK CREATED`
- `TASK UPDATED`
- `TASK CLOSED`

Each response includes the task id, current status, owner, and source channel.

## Explicitly out of scope

This phase does not include:

- WhatsApp task summary/list/show queries beyond the separate query bridge
- automatic delivery claims
- provider state reconciliation
- runtime auth or remote deployment
