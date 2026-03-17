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

Los `outputs` tambien pueden incluir resultados manuales de worker, por ejemplo una entrada `worker-result` con `source: codex_manual`, `status` y `summary`.

Las tareas raiz de cadena tambien pueden persistir:

- `chain_type` para identificar el tipo de cadena ejecutada
- `chain_status` para reflejar el estado interno de la orquestacion
- `chain_plan` para declarar los steps previstos y su metadata
- `chain_summary` para dejar una vista agregada de las child tasks

Las child tasks creadas como parte de una cadena tambien pueden persistir:

- `step_name` para mapearlas a un paso del plan
- `step_order` para mantener orden estable
- `critical` para definir si su falla rompe la cadena
- `execution_mode` para distinguir `local` de `worker`

Las tareas delegadas que entran en corrida controlada de Codex tambien pueden persistir:

- `worker_run` con paths de ticket/prompt/log
- comando ejecutado
- timestamps de inicio y fin
- `exit_code`
- estado interno de la corrida
- `result_status`
- `sandbox_mode`
- `decision_source`
- `policy_version`

Las tareas tambien pueden persistir un submodelo canónico de entrega user-facing en:

- `delivery.protocol_version`
- `delivery.minimum_user_facing_success_state`
- `delivery.current_state`
- `delivery.user_facing_ready`
- `delivery.visible_artifact_required`
- `delivery.visible_artifact_ready`
- `delivery.visible_artifact_deliveries`
- `delivery.whatsapp`
- `delivery.transitions`
- `delivery.claim_history`

Ese bloque no reemplaza `status`. Sirve para separar la aceptacion tecnica de la entrega real percibida por el usuario.

Las tareas tambien pueden persistir un submodelo canónico de screenshot host-side en:

- `screenshot.protocol_version`
- `screenshot.required`
- `screenshot.current_state`
- `screenshot.ready_for_claim`
- `screenshot.items`
- `screenshot.events`
- `screenshot.last_transition_at`
- `screenshot.last_verified_at`
- `screenshot.block_reason`
- `screenshot.fail_reason`

Ese bloque separa la simple captura host-side de la verdad visual verificada.

Cuando la tarea exige una entrega de artifact visible al usuario, `delivery.visible_artifact_deliveries` persiste la evidencia canónica de:

- destino pedido
- ruta resuelta
- ruta normalizada
- verificacion de existencia y lectura
- owner observado
- resultado final `PASS`, `BLOCKED` o `FAIL`

Cuando la tarea depende de verdad de canal por WhatsApp, `delivery.whatsapp` persiste la evidencia canónica de:

- state actual del canal
- confidence del delivery
- claim user-facing permitido
- `message_id` rastreado
- provider y destinatario
- intentos y claims auditables por task

Las tareas también pueden persistir un submodelo canónico de media en:

- `media.protocol_version`
- `media.required`
- `media.current_state`
- `media.ready`
- `media.allowed_for_delivery`
- `media.items`
- `media.events`

Ese bloque deja identidad material auditable para archivos y adjuntos antes de usarlos en un canal posterior.

El estado interno recomendado de `worker_run.state` en esta etapa es:

- `ready`
- `running`
- `finished`
- `failed`

## Estados validos

La primera version valida solamente estos estados:

- `queued`
- `running`
- `blocked`
- `delegated`
- `worker_running`
- `done`
- `failed`
- `cancelled`

Semantica practica de esta etapa:

- `pending` es la idea general de algo pendiente; el estado persistido equivalente es `queued`
- `blocked` significa que la tarea no pudo avanzar por una precondicion externa u operativa no satisfecha
- `failed` queda reservado para falla interna real o para una ejecucion no exitosa despues de haber podido correr

En runners que quieran una senal maquina estable, `blocked` puede aparecer junto con `outputs[].exit_code = 2`.

Las tareas raiz de cadena tambien pueden cerrar como `blocked` cuando una precondicion externa impide completar un paso critico sin que exista una falla interna real del motor.

Importante:

- `done` no significa automaticamente `visible`
- `accepted` y `delivered` no significan automaticamente exito percibido por el usuario
- el claim final de exito user-facing debe pasar por el submodelo `delivery` y alcanzar al menos `visible`

Tambien pueden quedar en `delegated` cuando la cadena ya avanzo hasta un paso worker manual-controlado y todavia espera un resultado registrado de ese worker.

Cuando ese resultado ya existe, la raiz de cadena puede volver a `running` mediante una reanudacion explicita y cerrar luego como `done`, `failed` o `blocked` segun el outcome real del worker y de los pasos restantes.

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

La base operativa minima queda cubierta por:

- `./scripts/task_new.sh <type> <title>`
- `./scripts/task_show.sh <task_id>`
- `./scripts/task_list.sh`
- `./scripts/task_update.sh <task_id> <status>`
- `./scripts/task_record_delivery_transition.sh <task_id> <state> <actor> <channel> <evidence>`
- `./scripts/task_delivery_summary.sh <task_id>`
- `./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]`
- `./scripts/task_spawn_child.sh <parent_task_id> <type> <title>`
- `./scripts/task_tree.sh <task_id>`
- `./scripts/task_chain_plan.sh <chain_type> <title>`
- `./scripts/task_chain_status.sh <task_id>`

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
