# OpenClaw Status Consistency Pack

Fecha de actualizacion: 2026-04-01

## Proposito

Este documento fija el contrato de lectura cruzada entre las tres superficies principales de estado usadas hoy en Golem:

- `openclaw gateway status`
- `openclaw status`
- `openclaw channels status --probe`

Su objetivo es dejar claro:

- que mira realmente cada superficie
- donde se pisan
- donde divergen
- que divergencias son normales
- que divergencias piden mas evidencia
- y que paquete minimo debe acompanar cualquier ticket futuro que use esta triangulacion

## Alcance

Este pack si cubre:

- comparacion explicita entre las tres superficies
- triangulacion read-side de control plane, summary general y estado de channels
- matriz de consistencia
- alineaciones esperables y divergencias esperables
- divergencias preocupantes que piden mas evidencia
- formato recomendado de `status triangulation brief`

## Fuera de alcance

Este pack no cubre:

- runtime vivo
- mutacion de gateway, services, config o channels
- delivery real
- browser usable
- readiness total del sistema
- reactivacion de WhatsApp
- `openclaw browser ...`
- workers, APD/docencia, host control total o channels live

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue congelado
- runtime vivo sigue fuera
- browser nativo sigue fuera

## Relacion con el status evidence pack

Orden correcto cuando un ticket dependa de triangulacion de estado:

1. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
2. `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
3. `docs/CAPABILITY_MATRIX.md`
4. `docs/CURRENT_STATE.md`
5. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- `status evidence pack`:
  - fija que evidencia minima vale para la familia `status`
- `status consistency pack`:
  - fija como interpretar juntas las tres superficies principales
- `capability matrix`:
  - conserva el detalle de observaciones y clasificaciones
- `current state`:
  - resume la lectura vigente
- `handoff`:
  - prioriza reentrada corta

## Comparacion de las tres superficies

### `openclaw gateway status`

Lectura principal:

- superficie mas `control plane focused`
- mira si el gateway local esta arriba y responde
- su senal fuerte hoy es `Runtime: running` + `RPC probe: ok`

Lo que aporta mejor que las otras:

- salud del gateway
- reachability del plano central
- base para decir si el control plane parece vivo

Lo que no aporta por si sola:

- resumen total del host
- detalle fino del canal
- delivery real

### `openclaw status`

Lectura principal:

- superficie mas `aggregate status`
- resume varias capas en una vista operativa corta
- sirve como fotografia general, no como prueba exhaustiva de cada subsistema

Lo que aporta mejor que las otras:

- resumen corto de salud general
- lectura humana rapida del estado actual
- base fuerte para reentrada y verdad operativa corta

Lo que no aporta por si sola:

- detalle fino del canal
- semantica exhaustiva de cada capability
- autorizacion para inferir readiness total

### `openclaw channels status --probe`

Lectura principal:

- superficie mas especifica del estado de channels
- sirve para ver detalle de conectividad, linking o estado de canal
- es la que mas facilmente muestra matices que `openclaw status` resume

Lo que aporta mejor que las otras:

- detalle del channel lane
- conectividad y detalle mas especifico del probe
- confirmacion o matiz del estado de canal visto desde el summary general

Lo que no aporta por si sola:

- salud total del sistema
- estado completo del control plane
- delivery real

## Matriz de consistencia

| surface | primary_focus | scope | strongest_use | weakest_use | expected_overlap | expected_divergence | unsafe_inference | supporting_docs | primary_verify | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `openclaw gateway status` | control plane | gateway local y rpc | probar que el plano central responde | resumir todo el host | debe ser coherente con una lectura sana del summary general | puede verse bien aunque un channel o un subsistema esten peor | "gateway sano = sistema totalmente listo" | `docs/CAPABILITY_MATRIX.md`, `docs/OPERATING_MODEL.md` | `./scripts/verify_openclaw_capability_truth.sh` | surface mas cercana al nucleo del control plane |
| `openclaw status` | aggregate status | resumen general del host OpenClaw | retome corto, snapshot operativo y lectura humana | detalle fino de cada subsistema | deberia reflejar que el gateway existe y resumir estado de channels | puede simplificar o ocultar matices que el probe de channel si muestra | "summary OK = browser, delivery o runtime listos" | `docs/CURRENT_STATE.md`, `docs/CAPABILITY_MATRIX.md`, `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md` | `./scripts/verify_openclaw_capability_truth.sh` | surface mas util para tickets de verdad operativa corta |
| `openclaw channels status --probe` | channel state | estado especifico del lane de channels | matizar conectividad y detalle del canal | hablar del sistema entero | deberia ser razonablemente compatible con lo que el summary general dice del canal | puede mostrar detalle mas especifico o wording distinto sin invalidar el summary | "connected = delivery real o canal listo para uso live" | `docs/CAPABILITY_MATRIX.md`, `docs/WHATSAPP_SAFETY_CONTRACT.md` | `./scripts/verify_openclaw_capability_truth.sh` | surface mas util para channel-specific reading |
| triangulacion conjunta | lectura cruzada | control plane + summary + channel detail | tickets de consistencia y snapshots robustos | autorizar acciones sobre runtime | debe permitir una imagen mas robusta que una sola surface | las diferencias de detalle son normales si la direccion general coincide | "tres surfaces juntas = permiso para tocar runtime" | `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`, `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md` | `./scripts/verify_openclaw_capability_truth.sh` | mejor uso: evidencia read-side mas fuerte, no poder operativo |

## Alineaciones y divergencias

### Alineaciones esperables

Casos razonablemente coherentes:

- `gateway status` muestra `Runtime: running` y `RPC probe: ok`
- `openclaw status` muestra una lectura general sana del gateway
- `channels status --probe` muestra el channel visible como reachable o connected

En esta situacion se puede decir:

- el control plane parece vivo
- el summary general y el probe del canal no se contradicen de forma fuerte
- hay base para una lectura operativa corta

### Divergencias esperables

Divergencias aceptables que no deben inflarse:

- `openclaw status` resume "WhatsApp ON OK" mientras `channels status --probe` muestra detalle mas especifico como `linked/running/connected`
- `channels status --probe` incluye wording o detalle de allowlist/pairing que el summary general no repite
- `gateway status` solo habla del control plane mientras las otras dos hablan de resumen y canal

Estas divergencias son normales porque:

- las superficies tienen foco distinto
- una resume
- otra detalla
- otra se centra en el control plane

### Divergencias preocupantes

Divergencias que deben empujar a pedir mas evidencia:

- `gateway status` no demuestra runtime/rpc sanos pero `openclaw status` parece demasiado optimista
- `openclaw status` insinua salud del canal pero `channels status --probe` no muestra conectividad comparable
- `channels status --probe` deja de ser reachable o connected cuando el summary general sigue sugiriendo normalidad
- el direction-of-truth entre las tres deja de ser compatible y no solo distinta en wording

Cuando pasa eso:

- no se toca runtime
- no se declara incidente automaticamente
- se pide mas evidencia read-side y se vuelve a citar capability matrix y verify primaria

## Evidencia minima de triangulacion

Para un ticket serio basado en triangulacion se exige, como minimo:

- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- una salida reciente de `./scripts/verify_openclaw_capability_truth.sh` o un artefacto versionado equivalente
- un `status triangulation brief` corto

No alcanza:

- una sola salida de `gateway status`
- una sola salida de `openclaw status`
- una sola salida de `channels status --probe`
- una captura de chat o una memoria del operador

## Formato recomendado de status triangulation brief

Formato minimo recomendado:

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
canonical_docs:
- docs/OPENCLAW_STATUS_EVIDENCE_PACK.md
- docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md
- docs/CAPABILITY_MATRIX.md
- docs/CURRENT_STATE.md
- handoffs/HANDOFF_CURRENT.md
limitations:
- no prueba delivery real
- no prueba browser usable
- no autoriza tocar runtime
short_conclusion: <3-5 lineas maximo>
```

Regla practica:

- el brief debe resumir las tres surfaces
- debe nombrar si la lectura esta alineada o si hay divergencia aceptable/preocupante
- debe cerrar con limites, no solo con optimismo

## Inferencias validas e invalidas

### Inferencias validas

La triangulacion si permite inferir:

- una imagen mas robusta del control plane y de la consistencia visible
- una base seria de reentrada operativa
- una lectura mas fuerte que usar una sola surface aislada

### Inferencias invalidas

La triangulacion no permite inferir:

- delivery real
- browser usable
- readiness total
- permiso para tocar runtime
- permiso para reactivar WhatsApp
- seguridad de channels live
- que cualquier divergencia sea un bug por si misma

## Como usar el pack para tickets futuros

Tickets que si nacen bien de esta triangulacion:

- ticket de consistencia entre surfaces
- ticket documental de verdad operativa
- ticket de reentrada corta
- ticket que versiona un snapshot triangulado del estado

Tickets que no deben nacer de esta triangulacion:

- runtime changes
- reactivar WhatsApp
- afirmar delivery real
- justificar login o pairing live
- reabrir browser nativo

Inputs minimos para un proximo ticket real apoyado en la triangulacion:

- pregunta concreta
- tres surfaces citadas
- verify primaria citada
- triangulation brief adjunto
- limites explicitamente repetidos

## Referencias canonicas

- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `./scripts/verify_openclaw_capability_truth.sh`

## Veredicto operativo

Las tres superficies no son equivalentes.

La lectura correcta hoy es:

- `openclaw gateway status` = control plane focused
- `openclaw status` = aggregate status
- `openclaw channels status --probe` = channel-specific detail

Usadas juntas, dan una lectura read-side mas fuerte.
No dan permiso para tocar runtime.
