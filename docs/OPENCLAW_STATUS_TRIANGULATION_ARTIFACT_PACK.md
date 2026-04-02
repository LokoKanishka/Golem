# OpenClaw Status Triangulation Artifact Pack

Fecha de actualizacion: 2026-04-01

## Proposito

Este pack materializa el `status triangulation brief` del consistency pack como un artefacto corto, reusable y versionable para tickets y retomes read-side.

Su objetivo es dejar una superficie canonica que permita:

- resumir juntas `openclaw gateway status`, `openclaw status` y `openclaw channels status --probe`
- citar las referencias canonicas minimas del repo
- fijar limites de inferencia visibles
- guardar un snapshot corto bajo una ruta estable y entendible

## Alcance

Este pack si cubre:

- la definicion exacta del `status triangulation artifact`
- el formato canonico minimo del artefacto
- la convencion de nombres y rutas
- cuando conviene generarlo
- cuando no alcanza
- el uso correcto del artefacto en tickets y retomes

## Fuera de alcance

Este pack no cubre:

- runtime vivo
- mutacion de gateway, channels, config o services
- delivery real
- browser usable
- readiness total del sistema
- reactivacion de WhatsApp
- `openclaw browser ...`
- channels live, workers, APD/docencia o host control total

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue fuera y congelado
- runtime vivo sigue fuera
- browser nativo sigue fuera

## Relacion con status evidence pack y status consistency pack

Orden correcto cuando se necesite un snapshot corto de estado:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
4. `docs/CAPABILITY_MATRIX.md`
5. `docs/CURRENT_STATE.md`
6. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status evidence pack`:
  - fija que cuenta como evidencia valida de la familia `status`
- `status consistency pack`:
  - fija como interpretar juntas las tres superficies principales
- `status triangulation artifact pack`:
  - fija como materializar esa triangulacion en un snapshot corto y reusable

## Definicion exacta del artifact

Un `status triangulation artifact` es un snapshot breve, versionable y estrictamente read-side que resume:

- lectura de `openclaw gateway status`
- lectura de `openclaw status`
- lectura de `openclaw channels status --probe`
- estado git minimo del repo
- verify primaria citada
- limitaciones explicitas

No es:

- una prueba total del sistema
- una sustitucion de `docs/CURRENT_STATE.md`
- una sustitucion de `handoffs/HANDOFF_CURRENT.md`
- una autorizacion para tocar runtime

## Formato canonico del artifact

Formato recomendado: `markdown` corto con bloque de campos canonicos y cierre breve.

Campos minimos obligatorios:

- `status_triangulation_at`
- `repo_branch`
- `repo_commit`
- `repo_dirty`
- `gateway_status_summary`
- `openclaw_status_summary`
- `channels_probe_summary`
- `alignment_or_divergence_note`
- `primary_verify`
- `primary_verify_result`
- `limitations`
- `short_conclusion`

Formato canonico minimo:

```text
status_triangulation_at: 2026-04-01T23:59:59Z
repo_branch: main
repo_commit: <sha>
repo_dirty: no
gateway_status_summary: Runtime running; RPC probe ok
openclaw_status_summary: gateway/control plane visible; summary general quoted
channels_probe_summary: linked/running/connected or equivalent quoted
alignment_or_divergence_note: aligned | acceptable divergence | divergence needs more evidence
primary_verify: ./scripts/verify_openclaw_capability_truth.sh
primary_verify_result: PASS|PARTIAL|BLOCKED|UNVERIFIED
limitations:
- no prueba delivery real
- no prueba browser usable
- no autoriza tocar runtime
short_conclusion: <3-5 lineas maximo>
```

Regla de tamano:

- el artefacto debe seguir siendo corto
- la conclusion final debe quedar en 3 a 5 lineas maximo
- no debe copiar enteras las salidas de las tres superficies

## Convencion de nombres y rutas

Ruta recomendada para artefactos generados:

- `outbox/manual/`

Nombre recomendado:

- `<timestamp>_status-triangulation-artifact_<slug>.md`

Ejemplo:

- `outbox/manual/20260401T235959Z_status-triangulation-artifact_quick-reentry.md`

Reglas:

- `timestamp` en UTC con formato `YYYYMMDDTHHMMSSZ`
- `slug` corto y humano, por ejemplo `quick-reentry`, `state-check`, `ticket-seed`
- el tipo de artefacto siempre debe decir `status-triangulation-artifact`

Ciclo de vida esperado:

- se genera on-demand
- puede adjuntarse a un ticket o usarse en un retome
- no hace falta versionar cada snapshot en git
- si un tramo depende de uno, debe citar su ruta exacta o copiar su fragmento minimo

## Cuando usarlo

Conviene generar un artifact cuando haga falta:

- reentrada rapida sin releer todo el proyecto
- ticket de verdad operativa corta
- ticket de consistencia read-side
- nota breve que necesite citar la triangulacion de estado junto con su verify primaria

## Cuando no alcanza

Este artifact no alcanza cuando el tramo requiere:

- decidir cambios de runtime
- justificar delivery real
- justificar browser usable
- justificar readiness total
- reabrir WhatsApp
- reemplazar `docs/CURRENT_STATE.md` o `handoffs/HANDOFF_CURRENT.md`

En esos casos hace falta volver a:

- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `./scripts/verify_openclaw_capability_truth.sh`

## Helper minima recomendada

Helper sugerida y versionada:

- `./scripts/render_status_triangulation_artifact.sh`

Rol de la helper:

- materializar el esqueleto canonico
- completar `timestamp`, `repo_branch`, `repo_commit` y `repo_dirty`
- emitir markdown a stdout o escribir un archivo bajo `outbox/manual/`

La helper no debe:

- tocar runtime
- ejecutar cambios
- vender el artifact como prueba total

## Inferencias validas e invalidas

### Inferencias validas

El artifact si permite inferir:

- una lectura corta y reusable de triangulacion read-side
- una base seria para retome rapido
- una evidencia mas fuerte que citar una sola salida aislada

### Inferencias invalidas

El artifact no permite inferir:

- delivery real
- browser usable
- readiness total
- permiso para tocar runtime
- permiso para reactivar WhatsApp
- seguridad de channels live

## Como usarlo en tickets y retomes

Uso correcto:

- citar el artifact junto con `docs/CURRENT_STATE.md` cuando se necesita resumen corto
- citar el artifact junto con `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md` cuando importa la lectura cruzada
- citar la verify primaria y su resultado junto con el artifact

Uso incorrecto:

- usar solo el artifact para justificar acciones
- tomar el artifact como reemplazo del estado canonico mas largo
- omitir las limitaciones

## Tickets que si deberian adjuntar un artifact

- ticket de verdad operativa corta
- ticket de reentrada rapida
- ticket de consistencia read-side

## Tickets que pueden vivir sin artifact

- actualizacion documental larga que ya cita `docs/CURRENT_STATE.md` y `handoffs/HANDOFF_CURRENT.md`
- tramo cuyo eje no es el estado sino baseline o mapping

## Tickets que no deben apoyarse solo en el artifact

- ticket que proponga runtime changes
- ticket que quiera inferir delivery real
- ticket que quiera inferir browser usable
- ticket que quiera reactivar WhatsApp

## Ejemplo canonico breve

```markdown
# OpenClaw Status Triangulation Artifact

status_triangulation_at: 2026-04-01T23:59:59Z
repo_branch: main
repo_commit: 3a198bc
repo_dirty: no
gateway_status_summary: Runtime running; RPC probe ok
openclaw_status_summary: summary general sano y alineado con el control plane
channels_probe_summary: detalle de channel visible como linked/running/connected
alignment_or_divergence_note: aligned
primary_verify: ./scripts/verify_openclaw_capability_truth.sh
primary_verify_result: PASS
limitations:
- no prueba delivery real
- no prueba browser usable
- no autoriza tocar runtime
short_conclusion: Las tres surfaces son coherentes para una lectura corta read-side. El artifact sirve para reentrada y tickets de consistencia, no para cambios operativos.
```

## Referencias canonicas

- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/verify_openclaw_capability_truth.sh`
