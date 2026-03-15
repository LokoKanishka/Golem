# Worker Result Packet

## Estado

Este protocolo define el formato canónico mínimo para importar un resultado de worker al modelo local actual de Golem.

No asume callbacks vivos ni integración host.
Sirve para bajar fricción operativa sin fingir automatización que todavía no existe.

## Objetivo

Permitir que un resultado de worker llegue como artifact parseable y que luego pueda:

- actualizar una child task delegada real
- alimentar `task_chain_settle.sh`
- alimentar `task_chain_reconcile_pending.sh`
- dejar trazabilidad duradera del ingreso

## Formato canónico actual

El formato recomendado en esta etapa es JSON.

Archivo esperado:

```text
*.worker-result.json
```

El packet debe ser legible por:

```text
./scripts/task_import_worker_result.sh <packet_path> [--settle]
```

## Campos mínimos

El packet canónico contempla al menos:

- `packet_kind`
- `packet_version`
- `generated_at`
- `child_task_id`
- `root_task_id`
- `worker_name`
- `source`
- `result_status`
- `summary`
- `notes`
- `artifact_paths`
- `commit_info`
- `evidence`

## Semántica de campos

### `packet_kind`

Debe ser:

```json
"worker_result_packet"
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

Task worker delegada que recibirá el resultado.

### `root_task_id`

Root chain asociada cuando aplica.
Es opcional fuera de chains, pero recomendada para chains mixtas.

### `worker_name`

Nombre humano del worker que produjo o entregó el resultado.

Ejemplos:

- `codex`
- `codex_manual`
- `codex_cli`

### `source`

Origen operativo del packet.

Ejemplos:

- `codex_manual`
- `codex_auto_extract`
- `operator_import`

### `result_status`

Estados permitidos:

- `done`
- `failed`
- `blocked`

### `summary`

Resumen corto y legible del outcome.

### `notes`

Lista opcional de notas adicionales.

### `artifact_paths`

Lista opcional de artifacts durables relevantes del resultado.

Deben apuntar a archivos existentes dentro del repo cuando el importador los registra.

### `commit_info`

Objeto opcional con metadatos de commit o branch.

Campos típicos:

- `commit`
- `branch`
- `remote`

### `evidence`

Objeto opcional con evidencia adicional parseable.

Campos típicos:

- `log_path`
- `result_artifact_path`
- `proof`

## Reglas mínimas

- el packet debe ser consistente con una child task real
- si `root_task_id` existe, debe coincidir con la root real del child
- el importador no inventa soporte multi-worker
- el packet no reemplaza `task_record_worker_result.sh`; lo alimenta
- el carril recomendado nuevo es `task_import_worker_result.sh`

## Flujo recomendado

Caso puntual:

```text
./scripts/task_import_worker_result.sh <packet_path> --settle
```

Caso por barrido posterior:

```text
./scripts/task_import_worker_result.sh <packet_path>
./scripts/task_chain_reconcile_pending.sh --apply
```

## Limitación actual honesta

La chain manual-controlada actual sigue soportando una sola worker child `await_worker_result` por root.

Por eso este packet:

- funciona bien para la child delegada real de esa root
- falla limpio si el packet es ambiguo o no coincide con la relación root/child real

## Ejemplo

Ver:

```text
protocols/examples/worker_result_packet.example.json
```
