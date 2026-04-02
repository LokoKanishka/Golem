# OpenClaw Status Triangulation Snapshot Workflow

Fecha de actualizacion: 2026-04-01

## Proposito

Este workflow operacionaliza el `OpenClaw Status Triangulation Artifact Pack` como una secuencia manual, corta y canonica para producir snapshots read-side consistentes.

Su objetivo es dejar claro:

- cuando conviene generar un `status triangulation artifact`
- que inputs minimos se exigen
- que outputs deben quedar
- que casos de uso son canonicos
- como se integra la helper `./scripts/render_status_triangulation_artifact.sh`

## Alcance

Este workflow si cubre:

- la secuencia minima para producir un snapshot corto
- tres casos canonicos de uso
- inputs minimos y outputs esperados por caso
- relacion entre artifact, verify y docs canonicas
- limites y no-usos del workflow

## Fuera de alcance

Este workflow no cubre:

- runtime vivo
- mutacion de gateway, channels, config o services
- delivery real
- browser usable
- readiness total
- reactivacion de WhatsApp
- `openclaw browser ...`
- scheduler, daemon, monitoreo continuo o background jobs

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue fuera y congelado
- runtime vivo sigue fuera
- browser nativo sigue fuera

## Relacion con artifact pack, status evidence pack y status consistency pack

Orden correcto cuando haga falta producir un snapshot usable:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
4. `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
5. `docs/CURRENT_STATE.md`
6. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status evidence pack`:
  - fija la evidencia minima de la familia `status`
- `status consistency pack`:
  - fija como interpretar juntas las tres superficies
- `status triangulation artifact pack`:
  - fija el formato canonico del artifact
- `status triangulation snapshot workflow`:
  - fija como usar ese artifact de forma consistente segun el caso

## Definicion del workflow minimo

Workflow minimo canonico:

1. decidir el caso de uso
2. resumir las tres surfaces
3. fijar la nota de alineacion o divergencia
4. citar la verify primaria y su resultado
5. renderizar el artifact con la helper
6. guardar el snapshot en `outbox/manual/` o citarlo en el ticket
7. adjuntar limites y docs canonicas del caso

Secuencia minima esperada:

- el workflow es manual y controlado
- el workflow no corre en background
- el workflow no reemplaza `docs/CURRENT_STATE.md`
- el workflow no reemplaza `./scripts/verify_openclaw_capability_truth.sh`

## Casos canonicos de uso

### Caso 1: retome rapido

Proposito:

- reubicar rapido el proyecto sin releer todo el corpus

Cuando usarlo:

- al volver a `main` despues de una pausa
- al abrir un tramo nuevo que depende de la triangulacion de status

Inputs minimos:

- `slug=quick-reentry`
- resumen corto de `openclaw gateway status`
- resumen corto de `openclaw status`
- resumen corto de `openclaw channels status --probe`
- nota de alineacion o divergencia
- resultado vigente de `./scripts/verify_openclaw_capability_truth.sh`
- conclusion corta con limites

Outputs esperados:

- artifact markdown corto en `outbox/manual/`
- referencia a `docs/CURRENT_STATE.md`
- referencia a `handoffs/HANDOFF_CURRENT.md`

Limitaciones:

- no reemplaza el handoff
- no alcanza para runtime changes

Verify o evidencia acompanante:

- `./scripts/verify_openclaw_capability_truth.sh`

### Caso 2: verdad operativa corta

Proposito:

- sostener una afirmacion breve y versionada sobre el estado visible del control plane y la consistencia general

Cuando usarlo:

- ticket de "que sabemos hoy"
- nota de estado previa a un tramo read-side

Inputs minimos:

- `slug=state-check`
- summaries concretos de las tres surfaces
- nota de alineacion, divergencia aceptable o divergencia que pide mas evidencia
- resultado reciente de la verify primaria
- conclusion corta con frontera explicita de no inferencia

Outputs esperados:

- artifact markdown corto en `outbox/manual/`
- cita de `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- cita de `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`

Limitaciones:

- no prueba delivery real
- no prueba browser usable

Verify o evidencia acompanante:

- `./scripts/verify_openclaw_capability_truth.sh`
- `docs/CAPABILITY_MATRIX.md`

### Caso 3: consistencia documental read-side

Proposito:

- dejar una evidencia corta cuando el foco es comparar wording y direccion de verdad entre las tres surfaces

Cuando usarlo:

- ticket documental de consistencia
- nota que quiere fijar si la triangulacion esta alineada o si pide mas evidencia

Inputs minimos:

- `slug=consistency-doc`
- tres summaries con wording suficientemente concreto
- nota explicita de alineacion o divergencia
- references a docs canonicas
- verify primaria citada

Outputs esperados:

- artifact markdown corto en `outbox/manual/`
- referencia a `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- referencia a `docs/CAPABILITY_MATRIX.md`

Limitaciones:

- no convierte una divergencia en incidente por si sola
- no autoriza tocar runtime

Verify o evidencia acompanante:

- `./scripts/verify_openclaw_capability_truth.sh`

## Inputs minimos por caso

Inputs obligatorios en todos los casos:

- `slug`
- `gateway_status_summary`
- `openclaw_status_summary`
- `channels_probe_summary`
- `alignment_or_divergence_note`
- `primary_verify_result`
- `short_conclusion`

Inputs opcionales pero utiles:

- lineas extra en `limitations`
- cita puntual de docs usadas en el ticket

Regla de variacion por caso:

- `retome rapido` prioriza `CURRENT_STATE` y `HANDOFF`
- `verdad operativa corta` prioriza `status evidence pack` y `capability matrix`
- `consistencia documental read-side` prioriza `status consistency pack` y direccion de verdad entre surfaces

## Outputs esperados por caso

Outputs siempre exigibles:

- artifact en ruta canonica de `outbox/manual/`
- slug consistente con el caso
- verify primaria citada
- conclusion corta con limites

Outputs situacionales:

- referencia a `docs/CURRENT_STATE.md` y `handoffs/HANDOFF_CURRENT.md` para retome
- referencia a `docs/CAPABILITY_MATRIX.md` para verdad operativa corta
- referencia a `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md` para consistencia documental

## Convencion de invocacion minima de la helper

La helper actual alcanza.
No requiere cambio funcional para este workflow.

Invocacion minima recomendada:

```bash
./scripts/render_status_triangulation_artifact.sh \
  --slug quick-reentry \
  --gateway-summary "Runtime running; RPC probe ok" \
  --openclaw-summary "summary general sano y alineado con el control plane" \
  --channels-summary "linked/running/connected visible en el probe" \
  --alignment-note "aligned" \
  --verify-result PASS \
  --short-conclusion "Las tres surfaces son coherentes para una lectura corta read-side. El artifact sirve para reentrada y tickets de consistencia, no para cambios operativos." \
  --write
```

Slugs recomendados por caso:

- `quick-reentry`
- `state-check`
- `consistency-doc`

Salida esperada:

- la helper imprime la ruta final generada
- el artifact queda en `outbox/manual/<timestamp>_status-triangulation-artifact_<slug>.md`

## Cuando usarlo

Conviene correr este workflow cuando haga falta:

- producir un snapshot corto y versionable
- abrir un ticket read-side apoyado en triangulacion de status
- dejar una reentrada corta sin reescribir `CURRENT_STATE`

## Cuando no alcanza

Este workflow no alcanza cuando el tramo requiere:

- decidir cambios de runtime
- justificar delivery real
- justificar browser usable
- justificar readiness total
- reactivar WhatsApp
- reemplazar `docs/CURRENT_STATE.md` o `handoffs/HANDOFF_CURRENT.md`

En esos casos hay que pedir mas evidencia y volver a:

- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `./scripts/verify_openclaw_capability_truth.sh`

## Tickets que si deberian usar este workflow

- ticket de retome rapido
- ticket de verdad operativa corta
- ticket de consistencia documental read-side

## Tickets que pueden vivir sin este workflow

- actualizacion documental larga apoyada directamente en `docs/CURRENT_STATE.md`
- tramo cuyo eje principal no es `status`

## Tickets que no deben apoyarse en este workflow

- ticket que quiera justificar runtime changes
- ticket que quiera inferir delivery real
- ticket que quiera inferir browser usable
- ticket que quiera reactivar WhatsApp

## Ejemplo canonico breve

```text
caso: quick-reentry
inputs_minimos:
- slug=quick-reentry
- tres summaries
- nota de alineacion
- verify primaria citada
output_esperado:
- outbox/manual/<timestamp>_status-triangulation-artifact_quick-reentry.md
```

## Referencias canonicas

- `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/render_status_triangulation_artifact.sh`
- `./scripts/verify_openclaw_capability_truth.sh`
