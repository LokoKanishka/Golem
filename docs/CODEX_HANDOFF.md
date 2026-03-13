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

## Como se inspecciona

Para ver el packet generado:

```text
./scripts/task_handoff_packet_show.sh <task_id>
```

## Uso manual con Codex

El flujo manual esperado es:

1. Golem delega una tarea y deja `handoff` persistido
2. Golem genera el handoff packet markdown
3. un operador humano usa ese packet como insumo para Codex
4. Codex ejecuta trabajo real fuera de esta capa

## Evolucion posible

Mas adelante esta capa podria evolucionar hacia:

- envio automatico del packet a un worker real
- agregados de session ids o worker ids
- callbacks de resultado
- actualizacion de outputs y artifacts de la tarea original

Ese paso no se implementa ahora. La meta actual es estandarizar el paquete de handoff antes de integrar ejecucion real.
