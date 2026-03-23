# Panel Visible Surface

This document defines the current visible local panel surface over the canonical task lane.

## Scope

This phase provides a minimal human-facing UI over the existing local HTTP API.

It supports:

- summary
- list
- show
- create
- update
- close

It does not support:

- auth
- remote deployment
- live WhatsApp bridge
- OpenClaw redesign

## Path

The visible surface is served by the same local HTTP server:

```text
python3 ./scripts/task_panel_http_server.py --host 127.0.0.1 --port 8765
```

Open:

```text
http://127.0.0.1:8765/panel/
```

## Contract

The UI does not call task files directly.

It consumes the existing local API only:

- `GET /tasks`
- `GET /tasks/<id>`
- `GET /tasks/summary`
- `POST /tasks`
- `POST /tasks/<id>/update`
- `POST /tasks/<id>/close`

That keeps the visible panel on the same contract already used by:

- `task_panel_read.sh`
- `task_panel_mutate.sh`
- `task_whatsapp_query.py`
- `task_whatsapp_mutate.py`

## UI capabilities

The visible panel provides:

- summary cards for the inventory
- task list with status and limit filter
- task detail view
- create form
- update form for the selected task
- close form for the selected task

## Verify

For the visible panel surface specifically, use:

```text
./tests/smoke_panel_visible_ui.sh
```

That smoke starts the local server, opens the visible panel in a real browser, exercises the canonical flow, and cleans up the test task at the end.
