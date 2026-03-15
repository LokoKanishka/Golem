# Codex Handoff

Este documento define el primer handoff packet estandar de Golem para Codex.

## Que es

Un handoff packet para Codex es un artefacto markdown generado desde una tarea ya delegada.

Su objetivo es transformar una tarea local con bloque `handoff` en un paquete claro, legible y reutilizable para trabajo manual con Codex.

## Que contiene

El packet incluye como minimo:

- `task_id`
- `type`
- `title`
- `objective`
- `status`
- datos del bloque `handoff`
- `notes`
- `outputs`
- `artifacts`
- una seccion final de objetivo de ejecucion para Codex

La idea es que Codex pueda leer una sola pieza y entender:

- que tarea es
- por que fue delegada
- que contexto ya existe
- que deberia hacer a continuacion

## Que no hace todavia

En esta etapa el packet no implica:

- ejecucion automatica de Codex
- callbacks
- ACP
- sincronizacion de estado en tiempo real
- cierre automatico de la tarea original

Es un puente documental y operativo, no una integracion viva.

## Como se genera

Se genera con:

```text
./scripts/task_prepare_codex_handoff.sh <task_id>
```

El script exige que la tarea:

- exista
- tenga estado `delegated`
- tenga bloque `handoff`

Si eso se cumple, crea:

```text
handoffs/<task_id>.md
```

Y en el carril recomendado actual también puede dejar:

```text
handoffs/<task_id>.packet.json
```

Segun la runtime artifact policy, este packet es evidencia persistible y durable a nivel local, pero no se trackea en Git por defecto.

## Como se inspecciona

Para ver el packet generado:

```text
./scripts/task_handoff_packet_show.sh <task_id>
```

## Relacion con el codex ticket

El handoff packet no es todavia el ticket final para Codex.

Sirve como capa intermedia entre:

- la tarea delegada en JSON
- el ticket listo para pegar en Codex

El ticket listo para Codex se genera aparte y agrega restricciones operativas, framing de ejecucion y formato de entrega esperado.

Ese ticket tambien es persistible como evidencia local, pero queda fuera de Git por defecto para evitar ruido operativo en el repo.

## Uso manual con Codex

El flujo manual esperado es:

1. Golem delega una tarea y deja `handoff` persistido
2. Golem genera el handoff packet markdown
3. Golem puede exportar un handoff packet JSON canónico y parseable
4. un operador humano usa el markdown y/o el ticket como insumo para Codex
5. Codex ejecuta trabajo real fuera de esta capa

El exportador machine-readable es:

```text
./scripts/task_export_worker_handoff.sh <task_id>
```

## Evolucion posible

Mas adelante esta capa podria evolucionar hacia:

- envio automatico del packet a un worker real
- agregados de session ids o worker ids
- callbacks de resultado
- actualizacion de outputs y artifacts de la tarea original

Ese paso no se implementa ahora. La meta actual es estandarizar el paquete de handoff antes de integrar ejecucion real.
