# Worker Result Flow

Este documento define como se cierra manualmente el loop entre una tarea delegada y el resultado de Codex.

## Relacion entre las piezas

El flujo actual queda asi:

1. una tarea se crea en `tasks/`
2. si corresponde, se delega a `worker_future`
3. se genera un handoff packet
4. se genera un codex ticket listo para uso manual
5. Codex trabaja fuera de esta capa
6. el operador registra el resultado manualmente en la tarea original

## Que se persiste al volver del worker

Cuando vuelve un resultado manual de Codex, la tarea registra:

- una entrada nueva en `outputs` con `kind: worker-result`
- `status` del resultado
- `summary`
- `source: codex_manual`
- artifacts opcionales si se pasan
- una nota de cierre en `notes`

## Estados permitidos despues del resultado

Una tarea en `delegated` puede pasar manualmente a:

- `done`
- `failed`

No se implementa todavia un estado de callback, worker activo o sincronizacion en tiempo real.

## Scripts

Registro del resultado:

```text
./scripts/task_record_worker_result.sh <task_id> <status> <summary> [--artifact <path> ...]
```

Resumen breve orientado a worker:

```text
./scripts/task_worker_summary.sh <task_id>
```

## Regla operativa

Este paso no ejecuta Codex ni valida automaticamente el contenido del resultado.

Solo deja trazabilidad formal y coherente dentro del modelo de tareas para cerrar manualmente el loop.
