# Worker Handoff

Esta documentacion define la primera capa formal de handoff hacia `worker_future`.

## Que es

Un handoff es una marca formal dentro de una tarea que indica:

- que la tarea fue evaluada como delegable
- que existe informacion minima suficiente para entregarla a un worker futuro
- que Golem no ejecuta ese worker todavia

## Que no es todavia

En esta etapa el handoff no implica:

- integracion real con Codex
- ejecucion remota
- colas vivas
- scheduling
- RPC, ACP o wrappers de ejecucion

Es solamente contrato y trazabilidad local.

## Informacion minima de handoff

El bloque `handoff` de una tarea debe incluir al menos:

- `delegated_to`
- `delegated_at`
- `task_type`
- `title`
- `objective`
- `recommended_next_step`
- `required_fields_present`

Tambien puede incluir campos auxiliares como:

- `policy_version`
- `source_status`
- `missing_required_fields`
- `rationale`

## Relacion entre task, delegation policy y worker_future

- la tarea sigue siendo el registro fuente de verdad
- `config/delegation_policy.json` define quien deberia resolver un tipo conocido hoy
- `config/worker_handoff_policy.json` define que tipos pueden quedar preparados para un worker futuro

La lectura operativa es:

1. si un tipo actual ya pertenece a `golem`, no deberia delegarse
2. si un tipo requiere humano o revision, tampoco deberia delegarse automaticamente
3. solo los tipos explicitamente habilitados en la policy de worker handoff pueden pasar a `delegated`

## Como se veria luego una integracion real

Una futura integracion real podria tomar el bloque `handoff` y:

- publicarlo a una cola
- iniciar un runner externo
- adjuntar un `worker_session_id`
- actualizar outputs y artifacts al volver

Nada de eso se implementa ahora. La meta actual es dejar un contrato estable y machine-readable para ese paso futuro.
