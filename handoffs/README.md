# Handoffs

Esta carpeta guarda evidencia local durable de delegacion y worker runs, junto con algunas trazas runtime-only de vida corta.

La politica completa vive en `docs/RUNTIME_ARTIFACT_POLICY.md`.

## Que queda en `handoffs/`

Persistible como evidencia local, pero fuera de Git por defecto:

```text
handoffs/<task_id>.md
handoffs/<task_id>.codex.md
handoffs/<task_id>.packet.json
handoffs/<task_id>.run.result.md
```

Esto sirve para:

- handoff durable
- ticket durable
- handoff machine-readable durable
- evidencia normalizada del resultado worker

## Que queda como runtime-only en `handoffs/`

Runtime local, regenerable o descartable, excluido de Git:

```text
handoffs/<task_id>.run.prompt.md
handoffs/<task_id>.run.log
handoffs/<task_id>.run.last.md
```

Esto sirve para:

- depuracion local
- inspeccion corta de una corrida reciente
- alimentar la extraccion hacia `run.result.md`

## Relacion entre `tasks/` y `handoffs/`

- `tasks/` sigue siendo la fuente de verdad del estado de la tarea
- `handoffs/` guarda evidencia derivada y auditable
- `handoffs/` tambien puede contener archivos operativos de vida corta

En otras palabras:

- la tarea registra el trabajo y su estado
- el handoff packet resume y empaqueta esa tarea para delegacion
- el codex ticket la deja lista para uso manual con Codex
- el handoff packet JSON deja una salida canónica machine-readable para la misma delegación
- el worker result deja una evidencia normalizada y duradera
- prompt/log/last message no son evidencia durable del repo

## Que no significa

Un handoff packet no es:

- trabajo ejecutado
- resultado final
- callback de worker
- evidencia de cierre

Es solamente un artefacto de delegacion.

## Regla vigente

La carpeta sigue ignorada por defecto.

Si algun archivo de `handoffs/` ya aparece trackeado en Git, se lo considera evidencia promovida intencionalmente y no un cambio de policy para todos los handoffs futuros.
