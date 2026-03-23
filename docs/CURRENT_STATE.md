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
- `task_validate.sh --all --strict` y `task_git_trace_check.sh` son los checks base del carril.

## Semantica del arbol
- `tasks/`: fuente de verdad operativa de las tareas activas y archivadas.
- `handoffs/`: evidencia durable versionable mas trazas runtime-only ignoradas.
- `openclaw/`: placeholders y scaffolding historico/documental; no modulo activo de despliegue.
- `state/live/`: snapshots de evidencia local sobre entorno/gateway, no estado vivo gobernado por Git.
