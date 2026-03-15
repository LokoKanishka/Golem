# Worker Result Flow

Este documento define como se cierra el loop entre una tarea delegada y el resultado de Codex, ya sea con cierre manual o con extraccion automatica asistida.

## Relacion entre las piezas

El flujo actual queda asi:

1. una tarea se crea en `tasks/`
2. si corresponde, se delega a `worker_future`
3. se genera un handoff packet
4. se genera un codex ticket listo para uso manual
5. opcionalmente Golem inicia una corrida controlada de Codex CLI
6. Codex trabaja y deja log/prompt/salida persistidos
7. el operador o script de cierre registra el resultado en la tarea original
8. opcionalmente Golem extrae un artifact final normalizado y resume el resultado automaticamente

## Que se persiste al volver del worker

Cuando vuelve un resultado de Codex, la tarea registra:

- una entrada nueva en `outputs` con `kind: worker-result`
- `status` del resultado
- `summary`
- `source: codex_manual` o `codex_auto_extract`
- artifacts opcionales si se pasan
- una nota de cierre en `notes`

Si un artifact pasado al script es Markdown (`.md`), ahora tambien debe cumplir la convencion minima documentada en `docs/OUTPUT_CONVENTIONS.md`.

Cuando hubo extraccion automatica, tambien puede persistir en `worker_run`:

- `extracted_summary`
- `extracted_summary_lines`
- `result_artifact_path`
- `result_source_files`

## Estados permitidos despues del resultado

Una tarea en `delegated` o `worker_running` puede pasar manualmente a:

- `done`
- `failed`
- `blocked`

No se implementa todavia un estado de callback, worker activo en background o sincronizacion en tiempo real.

## Scripts

Registro del resultado:

```text
./scripts/task_record_worker_result.sh <task_id> <status> <summary> [--artifact <path> ...]
```

Importacion desde packet canónico:

```text
./scripts/task_import_worker_result.sh <packet_path> [--settle]
```

Settlement operativo de vuelta hacia la chain:

```text
./scripts/task_chain_settle.sh <root_task_id|worker_task_id> [<done|failed|blocked> <summary> [--artifact <path> ...]]
```

Barrido operativo de roots delegadas pendientes:

```text
./scripts/task_chain_reconcile_pending.sh [--apply] [<root_task_id> ...]
```

Verificacion end-to-end del roundtrip packetizado:

```text
./scripts/verify_worker_packet_roundtrip.sh
```

Ese verify ahora tambien queda reconocido oficialmente en la capability matrix como:

```text
worker packet roundtrip
```

y corre en el carril de deep verify via:

```text
./scripts/verify_capability_matrix.sh
```

No forma parte del `self-check` operativo corto.

Corrida controlada:

```text
./scripts/task_start_codex_run.sh <task_id>
./scripts/task_finish_codex_run.sh <task_id> <status> <summary> [--artifact <path> ...]
./scripts/task_extract_worker_result.sh <task_id>
./scripts/task_finalize_codex_run.sh <task_id> <done|failed>
./scripts/task_worker_run_show.sh <task_id>
./scripts/task_worker_preflight.sh <task_id>
./scripts/task_worker_can_run.sh <task_id>
```

Validacion minima de artifacts Markdown:

```text
./scripts/validate_markdown_artifact.sh <path>
```

Resumen breve orientado a worker:

```text
./scripts/task_worker_summary.sh <task_id>
```

Protocolo canónico del packet:

```text
protocols/WORKER_RESULT_PACKET.md
protocols/examples/worker_result_packet.example.json
```

La salida canónica simétrica de delegación vive en:

```text
protocols/WORKER_HANDOFF_PACKET.md
protocols/examples/worker_handoff_packet.example.json
./scripts/task_export_worker_handoff.sh <task_id>
```

## Regla operativa

El cierre del resultado no valida automaticamente la calidad semantica del trabajo de Codex.

Pero si recibe artifacts Markdown, exige que no sean vacios, que tengan estructura minima y que lleven un timestamp trazable.

Cuando hubo una corrida controlada, tambien conserva trazabilidad de:

- ticket usado
- prompt efectivo
- log de la corrida
- salida final de Codex
- policy decision
- sandbox mode

Eso permite auditar la corrida sin convertirla todavia en una integracion automatica total.

En el carril manual-controlado de chains mixtas, `blocked` sirve para representar que el worker no pudo devolver un resultado util por una precondicion externa u operativa, sin disfrazarlo como falla interna del repo.

## Carril recomendado nuevo

El registro manual directo sigue soportado y no se elimina:

```text
./scripts/task_record_worker_result.sh ...
```

Pero el carril recomendado nuevo pasa a ser:

```text
./scripts/task_import_worker_result.sh <packet_path> --settle
```

Ese importador:

1. valida el packet canónico
2. valida que la child task delegada exista de verdad
3. registra el `worker-result` con metadatos útiles del packet
4. registra el packet como artifact de evidencia
5. opcionalmente dispara settlement sobre la chain

## Settlement recomendado para chains mixtas

Cuando un worker delegado pertenece a una root en `status: delegated` + `chain_status: awaiting_worker_result`, el cierre operativo recomendado pasa a ser:

```text
./scripts/task_chain_settle.sh <worker_task_id> <done|failed|blocked> "<summary>" [--artifact <path> ...]
```

Ese wrapper:

1. resuelve la root asociada
2. registra el resultado worker si todavia no estaba registrado
3. detecta si la root sigue realmente esperando
4. reanuda la chain cuando ya existe resultado suficiente
5. deja una salida `chain-settlement` trazable en la root

Tambien acepta una root directamente:

```text
./scripts/task_chain_settle.sh <root_task_id>
```

En ese modo:

- si todavia falta el resultado worker, devuelve `still_waiting`
- si el resultado ya existe, reconcilia y reanuda la root
- si la root ya estaba cerrada, responde como settlement no-op y deja evidencia

Limitacion actual honesta:

- el settlement soporta una sola worker child `await_worker_result` por root
- si una root expone varias al mismo tiempo, el script falla limpiamente y lo dice en vez de adivinar

## Sweep recomendado para varias roots delegadas

Cuando queres revisar varias roots manual-controladas sin acordarte cada ID, el barrido operativo recomendado es:

```text
./scripts/task_chain_reconcile_pending.sh
```

Ese modo no modifica nada y muestra por root:

- `root_id`
- `worker_child_id`
- `current_status`
- `chain_status`
- presencia o ausencia de resultado worker
- decision de reconciliacion sugerida

Para aplicar reconciliacion real solo sobre roots listas:

```text
./scripts/task_chain_reconcile_pending.sh --apply
```

Ese modo:

- no registra resultados nuevos por su cuenta
- no toca roots que siguen esperando resultado
- reutiliza `task_chain_settle.sh` solo cuando el resultado worker ya existe
- deja el estado final de cada root visible en la salida

Eso hace que los flujos queden asi:

- packet puntual: `task_import_worker_result.sh --settle`
- varios packets ya importados: `task_chain_reconcile_pending.sh --apply`
- roundtrip reproducible completo: `verify_worker_packet_roundtrip.sh`
- capability oficial deep verify: `verify_capability_matrix.sh` -> `worker packet roundtrip`

## Regla practica nueva

Si ya existe una corrida controlada terminada, el cierre recomendado pasa a ser:

```text
./scripts/task_finalize_codex_run.sh <task_id> <done|failed>
```

Ese wrapper genera primero un artifact final normalizado y luego reutiliza el mismo registro de `worker-result`.
