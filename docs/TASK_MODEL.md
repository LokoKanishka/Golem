# Task Model

Golem ya opera con tareas canonicas en repo.

Este documento describe el modelo vigente despues del cierre de transicion del carril de tareas.

## Objetivo

Tener una representacion versionada, auditable y coherente con el estado operativo real.

## Ubicacion

Cada tarea se guarda como un archivo JSON individual dentro de `tasks/`.

Formato de nombre:

```text
tasks/<task_id>.json
```

## Forma canonica vigente

La forma canonica minima sigue siendo repo-governed y strict-validatable por `scripts/task_validate.sh`.

Campos base:

- `id`
- `title`
- `objective`
- `status`
- `owner`
- `source_channel`
- `created_at`
- `updated_at`
- `acceptance_criteria`
- `evidence`
- `artifacts`
- `closure_note`
- `history`

Campos operativos admitidos en el carril actual:

- `task_id` como alias compatible del id
- `type`
- `origin`
- `canonical_session`
- `parent_task_id`
- `depends_on`
- `inputs`
- `outputs`
- `notes`
- `handoff`
- `delivery`
- `media`
- `screenshot`
- `step_name`
- `step_order`
- `critical`
- `execution_mode`
- `chain_type`
- `chain_status`
- `chain_plan`
- `chain_summary`
- `worker_run`

## Estados validos

El carril vigente acepta:

- `todo`
- `queued`
- `running`
- `blocked`
- `delegated`
- `worker_running`
- `done`
- `failed`
- `canceled`
- `cancelled`

`status` sigue siendo una lectura tecnica.
La verdad user-facing vive en `delivery`.

## Entry Point Canonico

- `./scripts/task_create.sh` es el entrypoint canonico.
- `./scripts/task_new.sh` queda solo como wrapper de compatibilidad.
- Las tareas nuevas deben nacer ya en forma strict-validatable.

## Relacion minima entre tareas

La primera capa de orquestacion local agrega dos campos simples:

- `parent_task_id`
- `depends_on`
- `step_name`
- `step_order`
- `critical`
- `execution_mode`

`parent_task_id` representa una relacion jerarquica minima entre una tarea y su tarea padre.

`depends_on` representa dependencias declarativas minimas hacia otras tareas, por ejemplo cuando una child task solo tiene sentido despues de que otra termine.

En esta etapa estos campos:

- no activan scheduling
- no bloquean ejecucion automaticamente
- no resuelven orden por si solos

Solo dejan trazabilidad estructural para coordinacion local y futura orquestacion.

## Scripts

La base operativa actual queda cubierta por:

- `./scripts/task_create.sh "Title" "Objective" --type <task_type>`
- `./scripts/task_show.sh <task_id>`
- `./scripts/task_list.sh`
- `./scripts/task_update.sh <task_id> <status>`
- `./scripts/task_validate.sh --all --strict`
- `./scripts/task_spawn_child.sh <parent_task_id> <type> <title>`

## Reglas de implementacion

- todo vive dentro del repo Golem
- no toca `~/.openclaw`
- no cambia configuracion viva del gateway
- no escribe artefactos en `outbox/`
- las escrituras se hacen en archivo temporal y se publican por reemplazo atomico

## Alcance actual

El modelo de tarea ya no es una fundacion abstracta.

Es el carril canonico vigente del repo y la base sobre la que ahora hay que integrar, verificar y reconciliar.
