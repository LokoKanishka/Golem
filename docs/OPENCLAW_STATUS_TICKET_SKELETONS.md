# OpenClaw Status Ticket Skeletons

Fecha de actualizacion: 2026-04-02

## Proposito

Este pack convierte una o dos instancias canonicas de `status` en esqueletos de ticket read-side que ya vienen casi listos para completarse con artifact real, verify concreta del momento y contexto puntual del tramo.

Su objetivo es dejar una biblioteca corta y versionada que ya no obligue a reinventar:

- patron de titulo
- objetivo base
- artifact requerida
- verify obligatoria
- outputs esperados
- fuera de alcance
- kill criteria
- y que campos quedan abiertos para completar en el momento

## Alcance

Este pack si cubre:

- estructura minima comun de un skeleton
- dos skeletons canonicos y concretos
- artifact y verify requeridas por skeleton
- campos fijos vs campos a completar
- guia de transformacion skeleton -> ticket real
- limites y no-usos explicitos

## Fuera de alcance

Este pack no cubre:

- runtime vivo
- delivery real
- browser usable
- readiness total
- reactivacion de WhatsApp
- `openclaw browser ...`
- channels live
- tickets ejecutables finales

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue fuera y congelado
- runtime vivo sigue fuera
- browser nativo sigue fuera

## Relacion con instantiation pack

Orden correcto de uso:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
4. `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
5. `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
6. `docs/OPENCLAW_STATUS_SEED_INSTANTIATION_EXAMPLES.md`
7. `docs/OPENCLAW_STATUS_TICKET_SKELETONS.md`
8. `docs/CURRENT_STATE.md`
9. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status seed instantiation examples`:
  - muestra como rellenar una seed con una pregunta real
- `status ticket skeletons`:
  - deja el formato casi listo para ticket, separando bloques fijos y bloques abiertos del momento

## Estructura minima de un skeleton

Todo skeleton canonico debe incluir, como minimo:

- `skeleton_id`
- `derived_from_instance`
- `recommended_title_pattern`
- `goal`
- `ready_fixed_sections`
- `fields_to_fill_at_run_time`
- `required_artifact_reference`
- `required_verify`
- `expected_outputs`
- `out_of_scope`
- `kill_criteria`
- `notes`

Regla de forma:

- los skeletons viven embebidos en esta doc canonica
- el skeleton no cambia la frontera de la instancia de origen
- el skeleton deja preparado el ticket, pero todavia no lo convierte en ejecucion

## Skeletons canonicos

### quick-reentry-skeleton-001

`skeleton_id`

- `quick-reentry-skeleton-001`

`derived_from_instance`

- `quick-reentry-instance-001`

`recommended_title_pattern`

- `Status quick reentry | <foco-del-tramo> | <fecha-o-commit>`

`goal`

- dejar un ticket de reentrada read-side que ubique rapido el frente actual sin releer todo el corpus ni derivar en accion operativa

`ready_fixed_sections`

- objetivo base de reentrada read-side
- bloque de artifact requerida
- bloque de verify obligatoria
- bloque de limites de inferencia
- bloque de `out_of_scope`
- bloque de `kill_criteria`

`fields_to_fill_at_run_time`

- `<foco-del-tramo>`
- `<fecha-o-commit>`
- ruta exacta del artifact `quick-reentry`
- summaries reales de las tres surfaces
- nota real de alineacion o divergencia
- conclusion corta del momento

`required_artifact_reference`

- `outbox/manual/<timestamp>_status-triangulation-artifact_quick-reentry.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- titulo de ticket completo y corto
- bloque de reentrada con referencias a `docs/CURRENT_STATE.md` y `handoffs/HANDOFF_CURRENT.md`
- conclusion read-side de 3 a 5 lineas
- pregunta siguiente todavia dentro de `status`

`out_of_scope`

- runtime changes
- delivery real
- browser usable
- reactivar WhatsApp

`kill_criteria`

- no existe artifact reciente o citada
- falta verify primaria o referencias de reentrada
- el skeleton se completa como si autorizara accion operativa

`notes`

- este skeleton sirve para volver al proyecto con una forma de ticket ya estable

### state-check-skeleton-001

`skeleton_id`

- `state-check-skeleton-001`

`derived_from_instance`

- `state-check-instance-001`

`recommended_title_pattern`

- `Status state check | <pregunta-read-side> | <fecha-o-commit>`

`goal`

- dejar un ticket read-side de verdad operativa corta que sostenga una afirmacion acotada sobre control plane y consistencia visible

`ready_fixed_sections`

- objetivo base de verdad operativa corta
- bloque de artifact requerida
- bloque de verify obligatoria
- bloque de outputs esperados
- bloque de `out_of_scope`
- bloque de `kill_criteria`

`fields_to_fill_at_run_time`

- `<pregunta-read-side>`
- `<fecha-o-commit>`
- ruta exacta del artifact `state-check`
- summaries reales de `gateway status`, `openclaw status` y `channels status --probe`
- nota real de alineacion, divergencia aceptable o evidencia faltante
- afirmacion corta sostenida por evidencia del momento

`required_artifact_reference`

- `outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_consistency_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- afirmacion corta y versionada sobre la verdad operativa visible
- limites repetidos explicitamente
- una siguiente pregunta read-side acotada o decision de cerrar el ticket como suficiente

`out_of_scope`

- delivery real
- browser usable
- readiness total
- cambios de runtime o config

`kill_criteria`

- falta artifact o verify primaria reciente
- el skeleton vende `status` como prueba total
- no quedan explicitadas las limitaciones de inferencia

`notes`

- este skeleton es el puente mas corto entre `state-check-instance-001` y un ticket real de status

## Artifact y verify por skeleton

Regla comun:

- todo skeleton canonico exige un `status triangulation artifact`
- todo skeleton canonico exige `./scripts/verify_openclaw_capability_truth.sh`

Refuerzo por skeleton:

- `quick-reentry-skeleton-001`:
  - artifact: `quick-reentry`
  - verify extra: artifact pack + snapshot workflow
  - docs canonicas: `docs/CURRENT_STATE.md`, `handoffs/HANDOFF_CURRENT.md`
- `state-check-skeleton-001`:
  - artifact: `state-check`
  - verify extra: consistency pack + snapshot workflow
  - docs canonicas: `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`, `docs/CAPABILITY_MATRIX.md`

Cuando alcanza:

- cuando el objetivo sigue siendo read-side y el ticket solo necesita una forma fuerte para completarse

Cuando no alcanza:

- si el ticket quiere salir de `status`
- si el ticket quiere tocar runtime
- si el ticket quiere inferir delivery real o browser usable

## Como convertir un skeleton en ticket real

Partes que ya vienen cerradas:

- patron de titulo
- objetivo base
- artifact requerida
- verify obligatoria
- fuera de alcance
- kill criteria

Partes que hay que completar en el momento:

- pregunta concreta
- fecha o commit exacta
- ruta exacta del artifact
- summaries reales de las tres surfaces
- conclusion corta

Secuencia minima:

1. elegir el skeleton correcto
2. ubicar o producir el artifact del slug correcto
3. citar la verify requerida
4. copiar `goal`, `out_of_scope` y `kill_criteria`
5. completar `fields_to_fill_at_run_time`

Regla:

- el skeleton todavia no es ticket ejecutable
- si al completarlo aparece necesidad de mutacion o live ops, ya no corresponde este pack

## Cuando usar estos skeletons

Conviene usarlos cuando haga falta:

- pasar de instancia a ticket casi completo
- redactar tickets read-side con menos friccion
- dejar una estructura comun para redaccion manual o tramos con Codex

## Cuando no alcanzan

Estos skeletons no alcanzan cuando el tramo requiere:

- runtime changes
- delivery real
- browser usable
- readiness total
- reactivar WhatsApp
- channels live

## Ejemplo breve de skeleton completable

```text
skeleton: state-check-skeleton-001
title_pattern: Status state check | <pregunta-read-side> | <fecha-o-commit>
artifact: outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md
fields_to_fill_at_run_time:
- pregunta concreta
- ruta exacta del artifact
- summaries reales
- conclusion corta
```

## Referencias canonicas

- `docs/OPENCLAW_STATUS_SEED_INSTANTIATION_EXAMPLES.md`
- `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/verify_openclaw_capability_truth.sh`
