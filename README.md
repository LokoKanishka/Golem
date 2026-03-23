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
- la migracion legacy ya cerro y el runner parametrizable queda consolidado en `scripts/task_migrate_legacy_batch.sh`;
- `handoffs/` conserva evidencia durable versionable, mientras que las trazas runtime-only siguen excluidas;
- `openclaw/` y `state/live/` quedan como estructura documental/evidencia, no como runtime gobernado desde este repo.

## Alcance Operativo

Este repo gobierna el carril canonico de tareas, su trazabilidad y la evidencia local necesaria para operar y auditar Golem.

No despliega OpenClaw ni controla servicios vivos desde Git.
