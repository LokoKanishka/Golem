# Task Contract

## Estado de este documento

Este contrato define el minimo deseado para una futura integracion operacional entre panel, repo y worker.

Todavia no esta implementado como integracion viva OpenClaw <-> Codex.
Hoy funciona como contrato doctrinal y de diseno.

El modelo local actual de tareas vive en `docs/TASK_MODEL.md`.
Este documento describe el contrato minimo hacia adelante.

## Objetivo

Definir una forma estable de hablar de una tarea sin suponer que hoy ya existe un worker real enchufado.

El contrato debe servir para:

- normalizar pedidos
- fijar una sesion canonica
- dejar un estado legible
- publicar eventos minimos
- permitir integrar un worker futuro sin rehacer el sistema

## Principios

- panel first: la sesion canonica debe remitir al panel del gateway
- WhatsApp auxiliar: puede pedir o reflejar, pero no reemplaza la sesion principal
- OpenClaw actual: el cuerpo operativo real sigue siendo OpenClaw
- Codex futuro: puede integrarse despues, pero no debe asumirse vivo hoy

## Campos minimos

El contrato minimo contempla estos campos:

- `task_id`: identificador unico y estable
- `origin`: origen del pedido, por ejemplo `panel`, `whatsapp`, `console`, `local`
- `canonical_session`: referencia a la sesion principal donde vive la verdad operativa
- `requested_by`: actor humano o sistema que hizo el pedido
- `objective`: objetivo textual de la tarea
- `repo_path`: repo involucrado cuando aplique
- `working_dir`: directorio de trabajo previsto
- `output_mode`: forma principal esperada de salida, por ejemplo `text`, `markdown_artifact`, `mixed`
- `outbox_dir`: directorio previsto para artifacts finales
- `notify_policy`: politica de notificacion o devolucion
- `status`: estado actual de la tarea

## Campo por campo

### `task_id`

Debe ser unico, estable y reutilizable en logs, artifacts y mensajes de estado.

### `origin`

Describe por donde entro el pedido.
No define por si solo la verdad principal.

### `canonical_session`

Debe apuntar a la superficie principal de seguimiento.
En esta etapa, la referencia canonicamente correcta debe pensar primero en el panel del gateway.

### `requested_by`

Identifica al solicitante o impulsor del pedido.
Puede ser una persona, un canal o un actor tecnico.

### `objective`

Es la formulacion breve y operativa del objetivo.

### `repo_path`

Identifica el repo de trabajo cuando la tarea es de repo, codigo o documentos.

### `working_dir`

Directorio operativo esperado para ejecutar el trabajo.

### `output_mode`

Declara la forma principal del resultado esperado.

Valores tipicos:

- `text`
- `markdown_artifact`
- `mixed`

### `outbox_dir`

Directorio previsto para artifacts finales cuando existan.

### `notify_policy`

Declara como debe devolverse o anunciarse el resultado.

Valores tipicos:

- `panel_only`
- `panel_then_whatsapp`
- `manual`
- `none`

### `status`

Estado operativo actual.

## Estados posibles

Para este contrato minimo, los estados permitidos son:

- `queued`
- `running`
- `delegated`
- `worker_running`
- `done`
- `failed`
- `cancelled`

Estos estados son compatibles con el modelo local actual del repo y alcanzan para esta etapa.

## Eventos minimos

Este contrato tambien necesita eventos minimos, aunque hoy no exista transporte vivo completo.

Eventos base:

- `task_created`
- `task_bound_to_canonical_session`
- `task_started`
- `task_progress`
- `task_delegated_future`
- `artifact_published`
- `task_completed`
- `task_failed`
- `task_cancelled`
- `notification_requested`

No todos estos eventos estan implementados hoy como capa viva.
Se definen para que el modelo futuro no se improvise despues.

## Politica de verdad

La verdad de una tarea debe resolverse con esta jerarquia:

1. `canonical_session` apunta a la sesion principal del panel del gateway
2. el repo guarda contratos, ejemplos y modelos versionados
3. los archivos locales de `tasks/` son registro local y prototipo operacional
4. WhatsApp puede reflejar o notificar, pero no se considera verdad principal
5. un worker futuro como Codex no sera verdad principal por si mismo; reporta de vuelta a la sesion canonica

## No implementar de mas en esta etapa

Este contrato no autoriza a afirmar que hoy ya existe:

- integracion viva OpenClaw <-> Codex
- scheduler real
- callbacks reales de worker
- ownership vivo de Codex sobre el sistema

Solo define el minimo correcto para no rehacer el modelo cuando esa integracion llegue.
