# Panel Task HTTP API

This document defines the minimal local HTTP surface over the canonical task lane.

## Scope

This API is local-only and repo-scoped.

It does not try to solve:

- remote exposure
- authentication
- multi-user coordination
- deployment
- WhatsApp integration

Its job is only to give the panel a small stable HTTP contract over the canonical task scripts already present in repo.

## Server

Start it with:

```text
python3 ./scripts/task_panel_http_server.py --host 127.0.0.1 --port 8765
```

Defaults:

- host: `127.0.0.1`
- port: `8765`

The server stays local and delegates internally to:

- `./scripts/task_panel_read.sh`
- `./scripts/task_panel_mutate.sh`

## Endpoints

### GET `/tasks`

Query params:

- `status`
- `limit`

Example:

```text
GET /tasks?limit=20
```

Delegates to:

```text
./scripts/task_panel_read.sh list ...
```

### GET `/tasks/<id>`

Example:

```text
GET /tasks/task-20260323T060405Z-b4c19ddb
```

Delegates to:

```text
./scripts/task_panel_read.sh show <id>
```

### GET `/tasks/summary`

Delegates to:

```text
./scripts/task_panel_read.sh summary
```

### POST `/tasks`

JSON body:

- `title` required
- `objective` required
- `type` optional
- `owner` optional
- `source` optional
- `accept` optional list
- `canonical_session` optional
- `origin` optional

Delegates to:

```text
./scripts/task_panel_mutate.sh create ...
```

### POST `/tasks/<id>/update`

JSON body fields supported:

- `status`
- `owner`
- `title`
- `objective`
- `source`
- `append_accept` list
- `note`
- `actor`

Delegates to:

```text
./scripts/task_panel_mutate.sh update <id> ...
```

### POST `/tasks/<id>/close`

JSON body:

- `status` required
- `note` required
- `owner` optional
- `actor` optional

Delegates to:

```text
./scripts/task_panel_mutate.sh close <id> ...
```

## Response shape

The server returns the JSON already produced by the canonical panel-side adapters.

That keeps the HTTP layer thin and avoids duplicating task logic.

In particular:

- read endpoints return the payloads from `task_panel_read.sh`;
- mutation endpoints return the payloads from `task_panel_mutate.sh`.

## Failure behavior

The server returns JSON errors and keeps the logic conservative:

- `404` for missing task routes or `task_not_found`;
- `400` for invalid input and canonical validation failures surfaced by the delegated script;
- `500` only when the delegated command fails unexpectedly.
