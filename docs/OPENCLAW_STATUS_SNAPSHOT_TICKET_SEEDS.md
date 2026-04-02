# OpenClaw Status Snapshot Ticket Seeds

Fecha de actualizacion: 2026-04-01

## Proposito

Este pack convierte el `OpenClaw Status Triangulation Snapshot Workflow` y el `OpenClaw Status Triangulation Artifact Pack` en seeds canonicas de tickets read-side.

Su objetivo es dejar una pequena biblioteca versionada que ya no obligue a reinventar:

- objetivo
- inputs minimos
- artifact requerido
- verify obligatoria
- outputs esperados
- kill criteria
- fuera de alcance

## Alcance

Este pack si cubre:

- estructura minima comun de una seed
- tres seeds canonicas y concretas
- artifact y verify requeridas por seed
- guia de transformacion seed -> ticket real
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
- scheduler, generador automatico o backlog completo

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue fuera y congelado
- runtime vivo sigue fuera
- browser nativo sigue fuera

## Relacion con workflow y artifact pack

Orden correcto de uso:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
4. `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
5. `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
6. `docs/CURRENT_STATE.md`
7. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status evidence pack`:
  - fija la evidencia minima de la familia `status`
- `status consistency pack`:
  - fija como leer juntas las tres surfaces
- `status triangulation artifact pack`:
  - fija el formato del artifact
- `status triangulation snapshot workflow`:
  - fija como producir el artifact por caso
- `status snapshot ticket seeds pack`:
  - fija como convertir todo eso en tickets concretos y repetibles

## Estructura minima de una seed

Cada seed canonica debe incluir, como minimo:

- `seed_id`
- `title`
- `goal`
- `canonical_use_case`
- `required_inputs`
- `required_artifacts`
- `required_verify`
- `expected_outputs`
- `out_of_scope`
- `kill_criteria`
- `notes`

Regla de forma:

- las seeds viven embebidas en esta doc canonica
- la estructura es markdown simple y legible
- cualquier seed futura debe copiar esta misma forma

## Seeds canonicas

### quick-reentry-seed

`seed_id`

- `quick-reentry-seed`

`title`

- `Status quick reentry snapshot`

`goal`

- producir un ticket corto de retome rapido que reubique el proyecto sin releer todo el corpus

`canonical_use_case`

- `quick-reentry`

`required_inputs`

- ultimo objetivo o pregunta concreta de reentrada
- artifact reciente producido con `slug=quick-reentry`
- summaries de `openclaw gateway status`, `openclaw status` y `openclaw channels status --probe`
- nota de alineacion o divergencia
- referencia a `docs/CURRENT_STATE.md`
- referencia a `handoffs/HANDOFF_CURRENT.md`

`required_artifacts`

- `outbox/manual/<timestamp>_status-triangulation-artifact_quick-reentry.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- ticket corto de reentrada
- resumen ejecutivo de 3 a 5 lineas
- referencias a `CURRENT_STATE` y `HANDOFF`
- limites explicitos de no inferencia

`out_of_scope`

- runtime changes
- delivery real
- browser usable
- reactivar WhatsApp

`kill_criteria`

- no existe artifact reciente o referenciable
- falta `CURRENT_STATE` o `HANDOFF`
- el ticket intenta escalar de snapshot a accion operativa

`notes`

- esta seed sirve para retomar contexto
- no reemplaza una auditoria larga

### state-check-seed

`seed_id`

- `state-check-seed`

`title`

- `Status operational truth check`

`goal`

- sostener una afirmacion read-side, breve y versionada sobre la verdad operativa corta del control plane y la consistencia visible

`canonical_use_case`

- `state-check`

`required_inputs`

- pregunta concreta de estado actual
- artifact reciente producido con `slug=state-check`
- summaries concretos de las tres surfaces
- nota de alineacion, divergencia aceptable o divergencia que pide mas evidencia
- referencias a `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- referencia a `docs/CAPABILITY_MATRIX.md`

`required_artifacts`

- `outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_consistency_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- ticket de verdad operativa corta
- afirmacion concreta sostenida por evidencia versionada
- limitaciones repetidas explicitamente
- siguiente pregunta read-side bien acotada

`out_of_scope`

- delivery real
- browser usable
- readiness total
- cambios de runtime o config

`kill_criteria`

- no hay verify primaria reciente ni artifact equivalente
- el ticket intenta vender `status` como capacidad total
- no quedan explicitadas las limitaciones

`notes`

- esta seed sirve para "que sabemos hoy"
- necesita mantener la frontera read-side

### consistency-doc-seed

`seed_id`

- `consistency-doc-seed`

`title`

- `Status consistency documentation check`

`goal`

- dejar un ticket documental read-side que compare wording y direccion de verdad entre las tres surfaces sin inflar divergencias

`canonical_use_case`

- `consistency-doc`

`required_inputs`

- pregunta concreta de consistencia documental
- artifact reciente producido con `slug=consistency-doc`
- summaries de las tres surfaces con wording suficientemente concreto
- nota explicita de alineacion o divergencia
- referencias a `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- referencias a `docs/CAPABILITY_MATRIX.md`

`required_artifacts`

- `outbox/manual/<timestamp>_status-triangulation-artifact_consistency-doc.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_consistency_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- ticket documental de consistencia
- descripcion clara de alineaciones o divergencias
- decision explicita sobre si hace falta mas evidencia read-side

`out_of_scope`

- declarar incidente runtime
- justificar acciones live
- inferir seguridad de channels live
- reabrir browser nativo o WhatsApp

`kill_criteria`

- la divergencia observada es solo de wording y se esta inflando como incidente
- falta artifact de triangulacion
- el ticket intenta pasar de consistencia documental a mutacion operativa

`notes`

- esta seed sirve para fijar drift documental
- no convierte una divergencia en bug por si sola

## Artifact y verify obligatorias por seed

Regla comun:

- toda seed canonica exige un `status triangulation artifact`
- toda seed canonica exige `./scripts/verify_openclaw_capability_truth.sh`

Refuerzo por seed:

- `quick-reentry-seed`:
  - artifact obligatorio: `quick-reentry`
  - verifies obligatorias: artifact pack + snapshot workflow
- `state-check-seed`:
  - artifact obligatorio: `state-check`
  - verifies obligatorias: capability truth + status consistency pack + snapshot workflow
- `consistency-doc-seed`:
  - artifact obligatorio: `consistency-doc`
  - verifies obligatorias: capability truth + consistency pack + artifact pack + snapshot workflow

No alcanza como evidencia:

- una sola salida de consola
- una memoria del operador
- una cita parcial de `CURRENT_STATE`
- un artifact sin verify primaria citada

## Como transformar una seed en ticket real

Partes que ya vienen fijas desde la seed:

- objetivo base
- artifact requerida
- verify obligatoria
- fuera de alcance
- kill criteria

Partes que hay que completar por contexto:

- pregunta concreta
- summaries reales de las tres surfaces
- nota de alineacion o divergencia
- conclusion corta
- ruta exacta del artifact usado

Secuencia minima:

1. elegir la seed correcta
2. producir o localizar el artifact correcto con la helper y el slug canonico
3. citar la verify obligatoria
4. copiar el objetivo, `out_of_scope` y `kill_criteria`
5. completar la pregunta concreta y los summaries reales

Regla:

- una seed no autoriza a cambiar su fuera de alcance
- si el ticket necesita romper esa frontera, ya no es esta seed

## Cuando usar estas seeds

Conviene usarlas cuando haga falta:

- redactar tickets read-side de reentrada
- redactar tickets de verdad operativa corta
- redactar tickets documentales de consistencia

## Cuando no alcanzan

Estas seeds no alcanzan cuando el tramo requiere:

- runtime changes
- delivery real
- browser usable
- readiness total
- reactivar WhatsApp
- channels live

En esos casos hace falta otro pack, otra evidencia y otra verify.

## Ejemplo breve de instanciacion

```text
seed: state-check-seed
question: Que sabemos hoy del control plane y la consistencia visible de status?
artifact: outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md
required_verify:
- ./scripts/verify_openclaw_capability_truth.sh
- ./scripts/verify_openclaw_status_consistency_pack.sh
```

## Referencias canonicas

- `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/render_status_triangulation_artifact.sh`
- `./scripts/verify_openclaw_capability_truth.sh`
