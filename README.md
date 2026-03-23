# golem

Golem es el sistema de agencia operativa donde:

- OpenClaw = golem/orquestador/interfaz
- Codex = worker despertable
- Panel del gateway = consola principal
- WhatsApp = canal auxiliar / control remoto / alertas
- Outbox = artefactos finales

## Principios
1. La sesión canónica vive en el panel.
2. WhatsApp no es el chat principal.
3. Codex no habla solo: OpenClaw lo despierta.
4. Los artefactos van a outbox.
5. Todo cambio importante debe quedar versionado.

## Estado del Repo

El repo ya no esta en bootstrap inicial.

Estado real actual:

- inventario activo saneado y gobernado desde `tasks/`;
- baseline final: `canonical=1395`, `legacy=0`, `corrupt=0`, `invalid=0`;
- `tasks/task-*.json` activas trackeadas por Git;
- entrypoint canonico de tareas: `scripts/task_create.sh`;
- `scripts/task_new.sh` queda solo como wrapper de compatibilidad;
- gate oficial del carril de tareas: `scripts/verify_task_lane_enforcement.sh`;
- path de lectura panel -> tareas canonicas: `scripts/task_panel_read.sh`;
- path de mutacion minima panel -> tareas canonicas: `scripts/task_panel_mutate.sh`;
- superficie HTTP local minima para panel -> tareas canonicas: `scripts/task_panel_http_server.py`;
- superficie operativa de la task API local serviceificada: `scripts/task_panel_http_ctl.py`;
- superficie visible minima del panel sobre la API local: `http://127.0.0.1:8765/panel/`;
- consultas minimas WhatsApp -> API local -> tareas canonicas: `scripts/task_whatsapp_query.py`;
- mutaciones minimas WhatsApp -> API local -> tareas canonicas: `scripts/task_whatsapp_mutate.py`;
- bridge/runtime local de WhatsApp sobre `openclaw logs --json --follow` + API local + `openclaw message send`: `scripts/task_whatsapp_bridge_runtime.py`;
- superficie operativa del bridge para start/stop/status/healthcheck: `scripts/task_whatsapp_bridge_ctl.py`;
- runner operativo diario del stack local task API + bridge: `scripts/golem_host_stack_ctl.sh`;
- runner de diagnostico operativo persistente del stack local: `scripts/golem_host_diagnose.sh`;
- la migracion legacy ya cerro y el runner parametrizable queda consolidado en `scripts/task_migrate_legacy_batch.sh`;
- `handoffs/` conserva evidencia durable versionable, mientras que las trazas runtime-only siguen excluidas;
- `openclaw/` y `state/live/` quedan como estructura documental/evidencia, no como runtime gobernado desde este repo.

## Alcance Operativo

Este repo gobierna el carril canonico de tareas, su trazabilidad y la evidencia local necesaria para operar y auditar Golem.

No despliega OpenClaw remoto ni controla infraestructura fuera del host local.

Si gobierna, en cambio, los wrappers y la documentacion de los servicios locales `systemd --user`
que sostienen el carril diario task API + bridge en esta maquina.
