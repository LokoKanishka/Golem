# Worker Handoff Packet

## Estado

Este protocolo define el formato canónico mínimo para exportar una delegación worker desde Golem.

No implica integración viva con el host ni ejecución automática del worker.
Sirve para que la ida tenga una pieza machine-readable simétrica al `WORKER_RESULT_PACKET`.

## Objetivo

Permitir que una child task delegada pueda salir del repo con un packet parseable que:

- complemente el handoff markdown humano
- complemente el ticket markdown para Codex
- preserve referencias cruzadas claras
- pueda ser reutilizado por futuros importadores o bridges sin rehacer el modelo

## Formato canónico actual

El formato recomendado en esta etapa es JSON.

Archivo esperado:

```text
handoffs/<task_id>.packet.json
```

Se genera con:

```text
./scripts/task_export_worker_handoff.sh <task_id>
```

## Campos mínimos

El packet canónico contempla al menos:

- `packet_kind`
- `packet_version`
- `generated_at`
- `child_task_id`
- `root_task_id`
- `origin`
- `requested_by`
- `worker_target`
- `worker_type`
- `objective`
- `repo_path`
- `working_dir`
- `canonical_session`
- `output_mode`
- `outbox_dir`
- `notify_policy`
- `await_worker_result`
- `critical`
- `continuation_policy`
- `artifact_paths`
- `notes`

## Semántica de campos

### `packet_kind`

Debe ser:

```json
"worker_handoff_packet"
```

### `packet_version`

Versión del formato.

Valor actual:

```json
"1.0"
```

### `generated_at`

Timestamp UTC ISO 8601 del packet.

### `child_task_id`

Task delegada que sale hacia el carril worker.

### `root_task_id`

Root chain asociada cuando aplica.
Puede quedar vacío fuera de una chain.

### `origin`

Origen operativo de la task local.

### `requested_by`

Solicitante humano o técnico si el dato existe.
En esta etapa puede quedar vacío honestamente.

### `worker_target`

Destino previsto del handoff.
Normalmente `worker_future`.

### `worker_type`

Tipo de trabajo o task type delegada.

### `objective`

Objetivo operativo que el worker debería resolver.

### `repo_path`

Repo de trabajo local.

### `working_dir`

Directorio operativo previsto.

### `canonical_session`

Referencia a la sesión canónica cuando exista.

### `output_mode`

Modo de salida esperado.
Puede quedar en `markdown_artifact`, `mixed` o un valor explícito ya persistido en la task.

### `outbox_dir`

Directorio previsto para resultados durables.

### `notify_policy`

Política de devolución si existe.
En esta etapa puede quedar como `manual`.

### `await_worker_result`

Marca si la root quedará esperando resultado manual-controlado.

### `critical`

Marca si el step delegado es crítico para la chain.

### `continuation_policy`

Objeto mínimo con la política de continuación conocida hoy.

Campos típicos:

- `await_worker_result`
- `continue_on_failed`
- `continue_on_blocked`
- `resume_via`
- `settle_via`
- `degradation_mode`

### `artifact_paths`

Lista de artifacts relevantes del outbound handoff.
Al menos debería incluir:

- `handoffs/<task_id>.md`
- `handoffs/<task_id>.codex.md`
- `handoffs/<task_id>.packet.json`

### `notes`

Lista opcional de notas operativas.

## Reglas mínimas

- la task debe ser realmente delegada o tener un bloque `handoff` consistente
- si `root_task_id` existe, debe coincidir con el padre real
- el packet no reemplaza el handoff markdown ni el Codex ticket
- el packet sí pasa a ser el carril machine-readable recomendado de salida
- el protocolo no finge soporte multi-worker si la chain actual no lo soporta

## Flujo recomendado

Flujo humano + machine-readable:

```text
./scripts/task_prepare_codex_handoff.sh <task_id>
./scripts/task_prepare_codex_ticket.sh <task_id>
./scripts/task_export_worker_handoff.sh <task_id>
```

En el flujo integrado actual, el export puede quedar disparado automáticamente por la preparación del handoff/ticket.

## Simetría con Worker Result Packet

La simetría actual queda así:

- ida: `WORKER_HANDOFF_PACKET`
- vuelta: `WORKER_RESULT_PACKET`

Ambos usan:

- JSON canónico
- `packet_kind`
- `packet_version`
- `generated_at`
- ids de task/root
- paths de artifacts durables
- notas opcionales

## Ejemplo

Ver:

```text
protocols/examples/worker_handoff_packet.example.json
```
