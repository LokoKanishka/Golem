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
- `parent_task_id`
- `depends_on`
- `status`
- `created_at`
- `updated_at`
- `title`
- `objective`
- `inputs`
- `outputs`
- `artifacts`
- `notes`

Campo opcional cuando aplica:

- `handoff`

Los `outputs` tambien pueden incluir resultados manuales de worker, por ejemplo una entrada `worker-result` con `source: codex_manual`, `status` y `summary`.

## Estados validos

La primera version valida solamente estos estados:

- `queued`
- `running`
- `delegated`
- `done`
- `failed`
- `cancelled`

## Convenciones iniciales

- `origin` se inicializa como `local`
- `canonical_session` se inicializa vacio
- `parent_task_id` se inicializa vacio si no aplica
- `depends_on` se inicializa como lista vacia
- `objective` arranca igual al `title`
- `inputs`, `outputs`, `artifacts` y `notes` arrancan como listas vacias
- `handoff` es opcional y aparece solo cuando una tarea queda preparada para `worker_future`
- `created_at` y `updated_at` usan timestamp UTC ISO 8601

## Relacion minima entre tareas

La primera capa de orquestacion local agrega dos campos simples:

- `parent_task_id`
- `depends_on`

`parent_task_id` representa una relacion jerarquica minima entre una tarea y su tarea padre.

`depends_on` representa dependencias declarativas minimas hacia otras tareas, por ejemplo cuando una child task solo tiene sentido despues de que otra termine.

En esta etapa estos campos:

- no activan scheduling
- no bloquean ejecucion automaticamente
- no resuelven orden por si solos

Solo dejan trazabilidad estructural para coordinacion local y futura orquestacion.

## Scripts

La base operativa minima queda cubierta por:

- `./scripts/task_new.sh <type> <title>`
- `./scripts/task_show.sh <task_id>`
- `./scripts/task_list.sh`
- `./scripts/task_update.sh <task_id> <status>`
- `./scripts/task_spawn_child.sh <parent_task_id> <type> <title>`
- `./scripts/task_tree.sh <task_id>`

## Reglas de implementacion

- todo vive dentro del repo Golem
- no toca `~/.openclaw`
- no cambia configuracion viva del gateway
- no escribe artefactos en `outbox/`
- las escrituras se hacen en archivo temporal y se publican por reemplazo atomico

## Alcance actual

Esto no es todavia un scheduler, ni una cola de workers, ni una integracion viva con el panel.

Es solamente la fundacion local del modelo de tarea para que Golem pueda hablar de trabajo estructurado con IDs, estados y metadata minima.

Tambien permite dejar una tarea en estado `delegated` con un bloque `handoff` persistido para una futura integracion con workers, sin ejecutar nada externo todavia.

Cuando un worker externo devuelve resultado de manera manual, la misma tarea puede cerrarse en `done` o `failed` dejando ese retorno persistido en `outputs` y `artifacts`.
