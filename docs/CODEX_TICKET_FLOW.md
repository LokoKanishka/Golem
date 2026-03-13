# Codex Ticket Flow

Este documento define la diferencia entre tarea, handoff packet y ticket listo para Codex.

## Capas

### Task JSON

La tarea en `tasks/<task_id>.json` es la fuente de verdad del sistema.

Ahí viven:

- estado
- metadata
- outputs
- artifacts
- bloque `handoff` si la tarea fue delegada

### Handoff packet

El handoff packet en `handoffs/<task_id>.md` es una vista legible de una tarea delegada.

Resume:

- datos principales de la tarea
- bloque `handoff`
- notas
- outputs
- artifacts

Su objetivo es empaquetar la delegacion en un solo artefacto humano-legible.

### Codex ticket

El codex ticket en `handoffs/<task_id>.codex.md` toma esa base y la convierte en instruccion de trabajo lista para usar con Codex.

Agrega:

- encabezado de proyecto y repo
- contexto operacional resumido
- objetivo explicito para Codex
- restricciones operativas
- entrega esperada

## Que agrega el codex ticket respecto del handoff packet

El handoff packet describe una delegacion.

El codex ticket describe una delegacion en formato de trabajo accionable para Codex.

En concreto agrega:

- framing de ejecucion
- restricciones explicitas
- criterio de entrega
- formato de respuesta esperado

## Como se genera

Se genera con:

```text
./scripts/task_prepare_codex_ticket.sh <task_id>
```

El script:

1. valida que la tarea exista
2. valida que este en `delegated`
3. valida que tenga `handoff`
4. genera primero el handoff packet si faltara
5. crea el ticket:

```text
handoffs/<task_id>.codex.md
```

## Como se usa manualmente con Codex

El flujo manual esperado es:

1. Golem delega una tarea
2. Golem genera handoff packet
3. Golem genera codex ticket
4. un operador pega ese ticket en Codex como instruccion controlada

## Por que este es el paso previo a una integracion real

Antes de automatizar ejecucion, callbacks o cierre de estado, conviene fijar una interfaz estable.

El codex ticket cumple ese rol:

- estandariza la forma de pedir trabajo
- reduce reconstruccion manual de contexto
- deja un contrato visible y versionable

Despues de esto, una integracion automatica podria usar este mismo formato o derivar uno equivalente estructurado.
