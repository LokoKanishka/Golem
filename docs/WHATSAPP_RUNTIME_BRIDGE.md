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

Por defecto:

- observa `openclaw logs --json --follow`;
- consume solo eventos `web-inbound` con etiqueta `inbound message`;
- clasifica comandos minimos de WhatsApp;
- delega queries a `./scripts/task_whatsapp_query.py`;
- delega mutaciones a `./scripts/task_whatsapp_mutate.py`;
- responde por `openclaw message send --channel whatsapp ...`.

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
python3 ./scripts/task_whatsapp_bridge_runtime.py --base-url http://127.0.0.1:8765
```

Flags utiles:

- `--send-dry-run`: no manda replies reales; usa `openclaw message send --dry-run`
- `--audit-file <path>`: guarda JSONL de eventos procesados
- `--state-file <path>`: persistencia minima de dedupe bajo `state/tmp/`
- `--replay-file <path>`: reprocesa un stream JSONL con shape real de `openclaw logs --json`

## Verify

El smoke dedicado es:

```text
./tests/smoke_whatsapp_bridge_runtime.sh
```

Ese smoke:

- levanta la API local de tareas;
- ejecuta el bridge en modo replay;
- usa eventos con el mismo shape que el runtime real de OpenClaw;
- valida `summary`, `list`, `show`, `create`, `update` y `close`;
- usa `openclaw message send --dry-run` para verificar la salida del canal sin dejar mensajes reales de prueba;
- limpia la tarea de smoke al final.

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
