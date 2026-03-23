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

The operational control surface lives in:

```text
./scripts/task_panel_http_ctl.py
```

The tracked `systemd --user` unit template lives in:

```text
./config/systemd-user/golem-task-panel-http.service.template
```

Defaults:

- host: `127.0.0.1`
- port: `8765`

The server stays local and delegates internally to:

- `./scripts/task_panel_read.sh`
- `./scripts/task_panel_mutate.sh`

## Service Mode

To install it as a persistent local service:

```text
python3 ./scripts/task_panel_http_ctl.py service-install --enable --host 127.0.0.1 --port 8765
python3 ./scripts/task_panel_http_ctl.py start --service --host 127.0.0.1 --port 8765
```

This service mode:

- reuses `./scripts/task_panel_http_server.py` directly;
- does not create another API;
- runs under `systemd --user`;
- exposes `start`, `stop`, `restart`, `status`, `logs` and `healthcheck`;
- uses `Restart=on-failure` for the main process.

## Daily Operations

Manual start:

```text
python3 ./scripts/task_panel_http_ctl.py start --host 127.0.0.1 --port 8765
```

Service start:

```text
python3 ./scripts/task_panel_http_ctl.py start --service --host 127.0.0.1 --port 8765
```

Status:

```text
python3 ./scripts/task_panel_http_ctl.py status
python3 ./scripts/task_panel_http_ctl.py status --json
python3 ./scripts/task_panel_http_ctl.py status --service
python3 ./scripts/task_panel_http_ctl.py status --service --json
```

Healthcheck:

```text
python3 ./scripts/task_panel_http_ctl.py healthcheck
python3 ./scripts/task_panel_http_ctl.py healthcheck --service
```

Restart:

```text
python3 ./scripts/task_panel_http_ctl.py restart
python3 ./scripts/task_panel_http_ctl.py restart --service
```

Stop:

```text
python3 ./scripts/task_panel_http_ctl.py stop
python3 ./scripts/task_panel_http_ctl.py stop --service
```

Logs:

```text
python3 ./scripts/task_panel_http_ctl.py logs
python3 ./scripts/task_panel_http_ctl.py logs --service --lines 200
```

Default local paths in manual mode:

- PID: `state/tmp/task_panel_http_server.pid`
- log: `state/tmp/task_panel_http_server.log`

The service healthcheck verifies at least:

- main process still running;
- `GET /tasks/summary` responds successfully.

## Install / Uninstall

Recommended host-local flow:

```text
python3 ./scripts/task_panel_http_ctl.py service-install --enable --host 127.0.0.1 --port 8765
python3 ./scripts/task_panel_http_ctl.py start --service --host 127.0.0.1 --port 8765
python3 ./scripts/task_panel_http_ctl.py status --service --host 127.0.0.1 --port 8765
python3 ./scripts/task_panel_http_ctl.py logs --service --host 127.0.0.1 --port 8765 --lines 100
```

To remove it:

```text
python3 ./scripts/task_panel_http_ctl.py service-uninstall
```

## Diagnose

If the local API fails, inspect in this order:

- `python3 ./scripts/task_panel_http_ctl.py healthcheck --service`
- `python3 ./scripts/task_panel_http_ctl.py status --service --json`
- `python3 ./scripts/task_panel_http_ctl.py logs --service --lines 200`
- `tail -n 100 state/tmp/task_panel_http_server.log`

## Bridge Coexistence

The default local URL remains:

```text
http://127.0.0.1:8765
```

That keeps the operational contract stable for the WhatsApp bridge service already running against the same local API surface.

If both services are installed, the intended host model is:

```text
task panel HTTP service -> local canonical task lane
whatsapp bridge service -> http://127.0.0.1:8765 -> same task panel HTTP service
```

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

## Verify

Relevant verify and smoke coverage:

```text
./tests/smoke_panel_task_http.sh
./tests/smoke_task_panel_http_service.sh
./tests/smoke_task_panel_bridge_service_stack.sh
```

The service smoke validates:

- real `systemd --user` install/start/status/healthcheck;
- task API operations over HTTP;
- clean restart;
- clean stop and absence of residual processes.

The coexistence smoke validates:

- task API service and WhatsApp bridge service can run together;
- the bridge can use the serviceified API with no manual HTTP server process;
- both services stop cleanly with no residual PIDs.
