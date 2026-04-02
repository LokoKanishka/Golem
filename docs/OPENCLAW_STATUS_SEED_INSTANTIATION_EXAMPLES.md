# OpenClaw Status Seed Instantiation Examples

Fecha de actualizacion: 2026-04-02

## Proposito

Este pack muestra como pasar de las seeds canonicas de `status` a instancias minimas y concretas, sin convertirlas todavia en tickets ejecutables.

Su objetivo es dejar ejemplos versionados que muestren:

- que cambia entre seed e instancia
- que artifact se referencia
- que verify acompana
- que outputs minimos se esperan
- que limites y kill criteria siguen arrastrandose

## Alcance

Este pack si cubre:

- estructura minima comun de una instancia
- tres instanciaciones canonicas y concretas
- artifact y verify requeridas por instancia
- guia de paso instancia -> ticket real
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

## Relacion con seeds pack

Orden correcto de uso:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
4. `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
5. `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
6. `docs/OPENCLAW_STATUS_SEED_INSTANTIATION_EXAMPLES.md`
7. `docs/CURRENT_STATE.md`
8. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status snapshot ticket seeds pack`:
  - fija la forma canonica del ticket seed
- `status seed instantiation examples`:
  - muestra como rellenar esa forma con preguntas reales del proyecto

## Estructura minima de una instancia

Toda instancia canonica debe incluir, como minimo:

- `instance_id`
- `derived_from_seed`
- `question_or_context`
- `goal`
- `required_inputs`
- `required_artifact_reference`
- `required_verify`
- `expected_outputs`
- `out_of_scope`
- `kill_criteria`
- `notes`

Regla de forma:

- las instancias viven embebidas en esta doc canonica
- cada instancia hereda limites de la seed de origen
- la instancia agrega contexto concreto, no cambia la frontera del seed

## Instanciaciones canonicas

### quick-reentry-instance-001

`instance_id`

- `quick-reentry-instance-001`

`derived_from_seed`

- `quick-reentry-seed`

`question_or_context`

- `Que necesito releer y citar hoy para retomar rapido el frente de status sin reabrir runtime ni WhatsApp?`

`goal`

- producir un esquema corto de retome que cite el artifact correcto, las docs correctas y la verify primaria correcta

`required_inputs`

- artifact de triangulacion con slug `quick-reentry`
- referencia a `docs/CURRENT_STATE.md`
- referencia a `handoffs/HANDOFF_CURRENT.md`
- resumen corto de las tres surfaces
- nota de alineacion o divergencia

`required_artifact_reference`

- `outbox/manual/<timestamp>_status-triangulation-artifact_quick-reentry.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- esquema corto de ticket de reentrada
- bloque de referencias a `CURRENT_STATE` y `HANDOFF`
- conclusion read-side de 3 a 5 lineas

`out_of_scope`

- runtime changes
- delivery real
- browser usable
- reactivar WhatsApp

`kill_criteria`

- no existe artifact reciente o citada
- no se puede nombrar la verify primaria
- el ejemplo intenta convertirse en plan de accion operativa

`notes`

- esta instancia muestra como usar `quick-reentry-seed` sobre una pregunta real de reubicacion

### state-check-instance-001

`instance_id`

- `state-check-instance-001`

`derived_from_seed`

- `state-check-seed`

`question_or_context`

- `Que sabemos hoy, en modo estrictamente read-side, sobre la verdad operativa corta del control plane y la consistencia visible entre las tres surfaces?`

`goal`

- producir un esquema minimo de ticket de verdad operativa corta con evidencia versionada y limites explicitos

`required_inputs`

- artifact de triangulacion con slug `state-check`
- verify primaria reciente
- resumen concreto de `gateway status`, `openclaw status` y `channels status --probe`
- referencia a `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- referencia a `docs/CAPABILITY_MATRIX.md`

`required_artifact_reference`

- `outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_consistency_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- afirmacion concreta y acotada de verdad operativa
- limites repetidos explicitamente
- siguiente pregunta read-side bien cerrada

`out_of_scope`

- delivery real
- browser usable
- readiness total
- cambios de runtime o config

`kill_criteria`

- la instancia usa `status` como si fuera capacidad total
- falta verify primaria o artifact equivalente
- no quedan explicitados los limites de inferencia

`notes`

- esta instancia es la forma minima de rellenar un `state-check-seed`

### consistency-doc-instance-001

`instance_id`

- `consistency-doc-instance-001`

`derived_from_seed`

- `consistency-doc-seed`

`question_or_context`

- `La diferencia de wording entre \`openclaw status\` y \`openclaw channels status --probe\` amerita mas evidencia read-side o solo una aclaracion documental?`

`goal`

- producir un esquema de ticket documental que compare surfaces sin inflar divergencias ni derivar en cambios operativos

`required_inputs`

- artifact de triangulacion con slug `consistency-doc`
- resumen de las tres surfaces con wording concreto
- nota explicita de alineacion o divergencia
- referencia a `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- referencia a `docs/CAPABILITY_MATRIX.md`

`required_artifact_reference`

- `outbox/manual/<timestamp>_status-triangulation-artifact_consistency-doc.md`

`required_verify`

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_openclaw_status_consistency_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh`
- `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh`

`expected_outputs`

- decision explicita sobre si la divergencia es aceptable o si pide mas evidencia
- nota documental corta
- limites repetidos sin ambiguedad

`out_of_scope`

- declarar incidente runtime
- justificar acciones live
- inferir seguridad de channels live
- reabrir browser nativo o WhatsApp

`kill_criteria`

- la divergencia observada es solo de wording y se la vende como bug
- no se puede referenciar artifact ni verify
- la instancia deriva en propuesta de mutacion operativa

`notes`

- esta instancia muestra como una pregunta documental concreta rellena `consistency-doc-seed`

## Artifact y verify por instancia

Regla comun:

- toda instancia canonica referencia un `status triangulation artifact`
- toda instancia canonica arrastra `./scripts/verify_openclaw_capability_truth.sh`

Refuerzo por instancia:

- `quick-reentry-instance-001`:
  - artifact: `quick-reentry`
  - verify extra: artifact pack + snapshot workflow
- `state-check-instance-001`:
  - artifact: `state-check`
  - verify extra: consistency pack + snapshot workflow
- `consistency-doc-instance-001`:
  - artifact: `consistency-doc`
  - verify extra: consistency pack + artifact pack + snapshot workflow

Cuando alcanza:

- cuando la instancia solo quiere dejar un esquema read-side y no pasar a ejecucion

Cuando todavia falta evidencia adicional:

- si la pregunta quiere salir de `status`
- si el caso quiere tocar runtime
- si el caso quiere inferir delivery real o browser usable

## Como convertir una instancia en ticket real

Partes que ya vienen cerradas:

- seed de origen
- objetivo base
- artifact requerida
- verify obligatoria
- fuera de alcance
- kill criteria

Partes que todavia hay que completar:

- ruta exacta del artifact usada
- summaries reales del momento
- conclusion corta
- decision de si la pregunta queda respondida o pide mas evidencia

Secuencia minima:

1. elegir la instancia correcta
2. ubicar o producir el artifact del slug correcto
3. citar la verify requerida
4. copiar `goal`, `out_of_scope` y `kill_criteria`
5. completar summaries y conclusion

Regla:

- la instancia sigue siendo read-side
- si el ticket necesita mutacion o live ops, ya no corresponde esta instancia

## Cuando usar estas instancias

Conviene usarlas cuando haga falta:

- mostrar rapidamente como se rellena una seed
- redactar tickets read-side sin inventar estructura
- dejar ejemplos de reentrada, verdad operativa o consistencia documental

## Cuando no alcanzan

Estas instancias no alcanzan cuando el tramo requiere:

- runtime changes
- delivery real
- browser usable
- readiness total
- reactivar WhatsApp
- channels live

## Ejemplo breve de paso a ticket

```text
instance: state-check-instance-001
derived_from_seed: state-check-seed
artifact: outbox/manual/<timestamp>_status-triangulation-artifact_state-check.md
required_verify:
- ./scripts/verify_openclaw_capability_truth.sh
- ./scripts/verify_openclaw_status_consistency_pack.sh
ticket_delta:
- completar summaries reales
- completar conclusion corta
- citar la ruta exacta del artifact
```

## Referencias canonicas

- `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/render_status_triangulation_artifact.sh`
- `./scripts/verify_openclaw_capability_truth.sh`
