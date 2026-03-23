# Task Git Trace Policy

## Decision

Desde este punto, las tareas activas canonicas `tasks/task-*.json` deben quedar trackeadas por Git.

## Reason

El proyecto definio que la tarea canonica vive en repo y gobierna la verdad operativa.
Si las tareas activas quedan ignoradas por Git, se rompe la trazabilidad entre:

- estado operativo real;
- historial visible en commits;
- auditoria posterior.

## Prior Finding

El gap detectado alrededor de `batch_15` mostro exactamente ese problema:
el baseline operativo avanzaba correctamente, pero Git no reflejaba los cambios
sobre `tasks/task-*.json` porque estaban ignoradas localmente.

## Policy

A partir de ahora:

- `tasks/task-*.json` activas deben ser visibles para Git;
- `tasks/archive/` sigue siendo repo-governed;
- `tasks/legacy_backup/` puede seguir trackeado como evidencia;
- `tasks/quarantine/` puede seguir trackeado como evidencia de incidentes.

## Important Note

El origen del problema fue local (`.git/info/exclude`), no una politica versionada del repo.
Por eso esta decision se acompana con un check explicito de trazabilidad.
