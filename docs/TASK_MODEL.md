# Task Model

Golem todavía no tiene un worker vivo integrado, pero ya necesita una nocion formal y local de tarea.

Esta primera fundacion vive completamente dentro del repo y no depende de OpenClaw ni de Codex en tiempo de ejecucion.

## Objetivo

Tener una representacion minima, estable y versionable de una tarea para:

- registrar trabajo pendiente o en curso
- mostrar estado
- actualizar progreso basico
- dejar una base clara para una integracion futura con sesiones canonicas y workers

## Ubicacion

Cada tarea se guarda como un archivo JSON individual dentro de `tasks/`.

Formato de nombre:

```text
tasks/<task_id>.json
```

## Campos minimos

Cada tarea incluye estos campos:

- `task_id`
- `type`
- `origin`
- `canonical_session`
- `status`
- `created_at`
- `updated_at`
- `title`
- `objective`
- `inputs`
- `outputs`
- `artifacts`
- `notes`

## Estados validos

La primera version valida solamente estos estados:

- `queued`
- `running`
- `done`
- `failed`
- `cancelled`

## Convenciones iniciales

- `origin` se inicializa como `local`
- `canonical_session` se inicializa vacio
- `objective` arranca igual al `title`
- `inputs`, `outputs`, `artifacts` y `notes` arrancan como listas vacias
- `created_at` y `updated_at` usan timestamp UTC ISO 8601

## Scripts

La base operativa minima queda cubierta por:

- `./scripts/task_new.sh <type> <title>`
- `./scripts/task_show.sh <task_id>`
- `./scripts/task_list.sh`
- `./scripts/task_update.sh <task_id> <status>`

## Reglas de implementacion

- todo vive dentro del repo Golem
- no toca `~/.openclaw`
- no cambia configuracion viva del gateway
- no escribe artefactos en `outbox/`
- las escrituras se hacen en archivo temporal y se publican por reemplazo atomico

## Alcance actual

Esto no es todavia un scheduler, ni una cola de workers, ni una integracion viva con el panel.

Es solamente la fundacion local del modelo de tarea para que Golem pueda hablar de trabajo estructurado con IDs, estados y metadata minima.
