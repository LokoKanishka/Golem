# Worker Result Flow

Este documento define como se cierra manualmente el loop entre una tarea delegada y el resultado de Codex.

## Relacion entre las piezas

El flujo actual queda asi:

1. una tarea se crea en `tasks/`
2. si corresponde, se delega a `worker_future`
3. se genera un handoff packet
4. se genera un codex ticket listo para uso manual
5. opcionalmente Golem inicia una corrida controlada de Codex CLI
6. Codex trabaja y deja log/prompt/salida persistidos
7. el operador o script de cierre registra el resultado en la tarea original

## Que se persiste al volver del worker

Cuando vuelve un resultado manual de Codex, la tarea registra:

- una entrada nueva en `outputs` con `kind: worker-result`
- `status` del resultado
- `summary`
- `source: codex_manual`
- artifacts opcionales si se pasan
- una nota de cierre en `notes`

Si un artifact pasado al script es Markdown (`.md`), ahora tambien debe cumplir la convencion minima documentada en `docs/OUTPUT_CONVENTIONS.md`.

## Estados permitidos despues del resultado

Una tarea en `delegated` o `worker_running` puede pasar manualmente a:

- `done`
- `failed`

No se implementa todavia un estado de callback, worker activo en background o sincronizacion en tiempo real.

## Scripts

Registro del resultado:

```text
./scripts/task_record_worker_result.sh <task_id> <status> <summary> [--artifact <path> ...]
```

Corrida controlada:

```text
./scripts/task_start_codex_run.sh <task_id>
./scripts/task_finish_codex_run.sh <task_id> <status> <summary> [--artifact <path> ...]
./scripts/task_worker_run_show.sh <task_id>
```

Validacion minima de artifacts Markdown:

```text
./scripts/validate_markdown_artifact.sh <path>
```

Resumen breve orientado a worker:

```text
./scripts/task_worker_summary.sh <task_id>
```

## Regla operativa

El cierre del resultado no valida automaticamente la calidad semantica del trabajo de Codex.

Pero si recibe artifacts Markdown, exige que no sean vacios, que tengan estructura minima y que lleven un timestamp trazable.

Cuando hubo una corrida controlada, tambien conserva trazabilidad de:

- ticket usado
- prompt efectivo
- log de la corrida
- salida final de Codex

Eso permite auditar la corrida sin convertirla todavia en una integracion automatica total.
