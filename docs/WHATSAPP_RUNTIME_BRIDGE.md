# WhatsApp Runtime Bridge

Este documento define el bridge/runtime local real de WhatsApp sobre el carril canonico de tareas.

## Objetivo

Resolver el path:

```text
WhatsApp real -> OpenClaw runtime/logs -> bridge local -> API HTTP local -> tareas canonicas
```

sin abrir una API nueva ni mutar `tasks/*.json` por fuera del carril ya consolidado.

## Superficie

El bridge vive en:

```text
./scripts/task_whatsapp_bridge_runtime.py
```

La superficie operativa de control vive en:

```text
./scripts/task_whatsapp_bridge_ctl.py
```

Por defecto:

- observa `openclaw logs --json --follow`;
- consume solo eventos `web-inbound` con etiqueta `inbound message`;
- clasifica comandos minimos de WhatsApp;
- delega queries a `./scripts/task_whatsapp_query.py`;
- delega mutaciones a `./scripts/task_whatsapp_mutate.py`;
- responde por `openclaw message send --channel whatsapp ...`;
- persiste estado operativo/heartbeat en `state/tmp/whatsapp_task_bridge_runtime_runtime.json`;
- soporta reinicio del follower de logs si el stream cae.

## Comandos soportados

Queries:

- `summary`
- `task summary`
- `tasks summary`
- `tasks list [status <x>] [limit <n>]`
- `task show <task-id>`

Mutaciones:

- `task create title=... ; objective=... ; ...`
- `task update <task-id> status=... ; ...`
- `task close <task-id> status=done ; note=...`

## Como levantarlo

Con la API local ya disponible:

```text
python3 ./scripts/task_panel_http_server.py --host 127.0.0.1 --port 8765
python3 ./scripts/task_whatsapp_bridge_ctl.py start --base-url http://127.0.0.1:8765
```

Flags utiles:

- `--send-dry-run`: no manda replies reales; usa `openclaw message send --dry-run`
- `--audit-file <path>`: guarda JSONL de eventos procesados
- `--state-file <path>`: persistencia minima de dedupe bajo `state/tmp/`
- `--replay-file <path>`: reprocesa un stream JSONL con shape real de `openclaw logs --json`
- `--log-file <path>`: captura salida operativa del bridge

## Operacion diaria

Arranque:

```text
python3 ./scripts/task_whatsapp_bridge_ctl.py start --base-url http://127.0.0.1:8765
```

Estado:

```text
python3 ./scripts/task_whatsapp_bridge_ctl.py status
python3 ./scripts/task_whatsapp_bridge_ctl.py status --json
```

Salud:

```text
python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck
```

Parada limpia:

```text
python3 ./scripts/task_whatsapp_bridge_ctl.py stop
```

El healthcheck verifica, como minimo:

- proceso principal vivo;
- runtime en `status: running`;
- heartbeat reciente;
- API local de tareas alcanzable por `GET /tasks/summary`.

## Logs y diagnostico

Por defecto, el wrapper operativo usa:

- PID: `state/tmp/whatsapp_task_bridge_runtime.pid`
- log: `state/tmp/whatsapp_task_bridge_runtime.log`
- estado runtime: `state/tmp/whatsapp_task_bridge_runtime_runtime.json`
- dedupe state: `state/tmp/whatsapp_task_bridge_runtime_state.json`
- audit trail: `state/tmp/whatsapp_task_bridge_runtime_audit.jsonl`

Si falla, mirar en este orden:

- `python3 ./scripts/task_whatsapp_bridge_ctl.py healthcheck`
- `python3 ./scripts/task_whatsapp_bridge_ctl.py status --json`
- `tail -n 100 state/tmp/whatsapp_task_bridge_runtime.log`
- `tail -n 50 state/tmp/whatsapp_task_bridge_runtime_audit.jsonl`

## Verify

El smoke dedicado es:

```text
./tests/smoke_whatsapp_bridge_runtime.sh
./tests/smoke_whatsapp_bridge_runtime_hardening.sh
```

El smoke base:

- levanta la API local de tareas;
- ejecuta el bridge en modo replay;
- usa eventos con el mismo shape que el runtime real de OpenClaw;
- valida `summary`, `list`, `show`, `create`, `update` y `close`;
- usa `openclaw message send --dry-run` para verificar la salida del canal sin dejar mensajes reales de prueba;
- limpia la tarea de smoke al final.

El smoke de hardening:

- levanta la API local;
- arranca el bridge por `task_whatsapp_bridge_ctl.py start`;
- inyecta eventos en vivo sobre un stream local seguido por `tail -f`;
- verifica `healthcheck` durante la operacion;
- apaga el bridge por `task_whatsapp_bridge_ctl.py stop`;
- confirma ausencia de pid residual y `status: stopped`.

## Limite honesto actual

En este entorno, OpenClaw expone runtime real conectado y `openclaw message send`,
pero no expone una superficie CLI repo-local para inyectar un inbound real de WhatsApp
durante el smoke.

Por eso:

- el bridge de produccion corre sobre `openclaw logs --json --follow`;
- el smoke usa replay de eventos inbound con shape real del runtime;
- la salida al canal sigue verificandose por el CLI oficial de OpenClaw.

## Fuera de alcance

Queda fuera en esta fase:

- auth compleja;
- despliegue remoto;
- systemd/servicio host desde este repo;
- producto final de chat;
- una segunda interfaz especial para WhatsApp.
