# Current State

Este archivo documenta el estado real actual del repo despues del cierre de transicion del carril de tareas.

## Baseline operativo vigente
- Inventario activo saneado.
- Baseline final:
  - canonical: 1395
  - legacy: 0
  - corrupt: 0
  - invalid: 0
- `tasks/task-*.json` activas ya trackeadas por Git.
- El runner parametrizable de migracion legacy ya reemplazo a los batch scripts especificos.
- El problema abierto del repo ya no es bootstrap: es integracion y reconciliacion futura sobre un carril canonico estable.

## Regla de tareas
- Entry point canonico: `scripts/task_create.sh`.
- `scripts/task_new.sh` queda solo como wrapper de compatibilidad para runners y verifies viejos.
- Gate oficial del carril: `./scripts/verify_task_lane_enforcement.sh`.
- El gate oficial incluye `task_entrypoint_policy_check.sh`, `verify_task_cli_minimal.sh`, `task_git_trace_check.sh`, `task_validate.sh --all --strict` y `tests/smoke_task_core.sh`.
- El path read-only para panel/backend inmediato sobre tareas canonicas es `./scripts/task_panel_read.sh`.
- El path de mutacion minima para panel/backend inmediato sobre tareas canonicas es `./scripts/task_panel_mutate.sh`.
- La superficie HTTP local minima sobre ese mismo carril es `./scripts/task_panel_http_server.py`.
- El path de consultas minimas por WhatsApp sobre la misma API local es `./scripts/task_whatsapp_query.py`.

## Semantica del arbol
- `tasks/`: fuente de verdad operativa de las tareas activas y archivadas.
- `handoffs/`: evidencia durable versionable mas trazas runtime-only ignoradas.
- `openclaw/`: placeholders y scaffolding historico/documental; no modulo activo de despliegue.
- `state/live/`: snapshots de evidencia local sobre entorno/gateway, no estado vivo gobernado por Git.
