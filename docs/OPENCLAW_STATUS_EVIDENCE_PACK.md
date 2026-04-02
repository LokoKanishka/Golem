# OpenClaw Status Evidence Pack

Fecha de actualizacion: 2026-04-01

## Proposito

Este documento fija el paquete canonico de evidencia para la familia `status` dentro de Golem.

Su objetivo es evitar que futuros tickets de:

- estado
- salud
- consistencia
- reentrada
- situacion actual

vuelvan a apoyarse en intuiciones, chat suelto o una sola salida de consola.

El `status pack` define:

- que cuenta como evidencia valida de `status`
- que documentos y scripts del repo forman su base
- cual es la verify primaria
- que formato minimo deberia tener un `status brief`
- que puede y que no puede inferirse desde `status`

## Alcance

Este pack si cubre:

- el uso de `status` como familia de verdad operativa corta
- la evidencia minima para tickets y retomes basados en `status`
- la relacion entre `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md`, `handoffs/HANDOFF_CURRENT.md` y `./scripts/verify_openclaw_capability_truth.sh`
- un formato recomendado de `status brief`
- limites de inferencia y reglas de uso

## Fuera de alcance

Este pack no cubre:

- runtime vivo
- mutaciones de gateway/services/systemd/config
- `openclaw browser ...`
- channels live
- delivery real
- readiness total del sistema
- reactivacion de WhatsApp
- workers, APD/docencia, plugins comunitarios o host control total

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue fuera y congelado
- browser nativo sigue fuera
- runtime vivo sigue fuera

## Relacion con baseline pack y mapping pack

Orden correcto de lectura cuando un tramo depende de `status`:

1. `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
2. `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
3. `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
4. `docs/CURRENT_STATE.md`
5. `handoffs/HANDOFF_CURRENT.md`

Reparto de roles:

- baseline pack:
  - dice por que CLI + channels es la baseline publica aceptada
- mapping pack:
  - aterriza cada familia a surfaces reales del repo
- status pack:
  - dice que evidencia minima exigir cuando la familia elegida es `status`
- current state:
  - resume la lectura vigente y los congelamientos
- handoff:
  - optimiza la reentrada humana corta

Este documento no reemplaza a `docs/CAPABILITY_MATRIX.md`.
Lo usa como base detallada.

## Que significa usar `status` en Golem

Usar `status` en Golem significa apoyar una afirmacion en evidencia read-side y versionable sobre:

- salud del control plane
- consistencia de surfaces de estado
- fotografia corta del host/proyecto
- reentrada rapida

La familia `status` es fuerte porque hoy si tiene:

- docs canonicas
- verify primaria
- resumen vigente
- handoff vigente

Pero sigue siendo una familia acotada.
No autoriza a extender su alcance a delivery, runtime mutation o capacidad total.

## Que cuenta como evidencia valida de `status`

La evidencia valida de `status` debe combinar, como minimo, cuatro piezas:

- una referencia canónica de interpretacion:
  - `docs/CAPABILITY_MATRIX.md`
- un resumen vigente del proyecto:
  - `docs/CURRENT_STATE.md`
- una guia de reentrada:
  - `handoffs/HANDOFF_CURRENT.md`
- una verify primaria o un artefacto versionado equivalente:
  - `./scripts/verify_openclaw_capability_truth.sh`

Evidencia adicional que puede reforzar un ticket sin ser suficiente por si sola:

- `./scripts/self_check.sh`
- extractos concretos y acotados de `openclaw gateway status`
- extractos concretos y acotados de `openclaw status`
- extractos concretos y acotados de `openclaw channels status --probe`
- hash/commit/branch del repo al momento del snapshot

Evidencia que no alcanza por si sola:

- una frase de chat
- una sola salida de `openclaw status`
- una sola linea de `channels status --probe`
- una captura mental del operador
- una doc publica sin cruce con el repo

## Superficies canonicas del pack

Documentos canonicos:

- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`

Scripts canonicos:

- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/self_check.sh`

Regla operativa:

- `./scripts/verify_openclaw_capability_truth.sh` es la verify primaria
- `./scripts/self_check.sh` es check de apoyo rapido, no reemplazo de la verify primaria

## Matriz de evidencia minima

| use_case | evidence_required | canonical_docs | canonical_verify | optional_supporting_artifacts | unsafe_shortcuts | notes |
| --- | --- | --- | --- | --- | --- | --- |
| Retome rapido | `CURRENT_STATE` + `HANDOFF` + `status pack` + ultimo veredicto de `verify_openclaw_capability_truth` o artefacto equivalente | `docs/CURRENT_STATE.md`, `handoffs/HANDOFF_CURRENT.md`, `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md` | `./scripts/verify_openclaw_capability_truth.sh` | `git log --oneline -8`, `git status --short` | leer solo el handoff o solo una linea de consola | caso mas comun de reubicacion |
| Ticket de verdad operativa | status pack + capability matrix + current state + verify primaria reciente | `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md`, `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md` | `./scripts/verify_openclaw_capability_truth.sh` | snippet corto de `gateway status`, `status`, `channels status --probe` | vender la prueba como si cubriera runtime completo | usar cuando el ticket diga "que sabemos hoy" |
| Ticket de consistencia de estado | capability matrix + current state + verify primaria + explicacion de diferencias entre surfaces | `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md` | `./scripts/verify_openclaw_capability_truth.sh` | `./scripts/self_check.sh` | asumir equivalencia textual total entre surfaces | sirve para discutir gaps o drift de estado |
| Ticket documental apoyado en status | status pack + mapping pack + current state + citas puntuales de capability matrix | `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`, `docs/CURRENT_STATE.md`, `docs/CAPABILITY_MATRIX.md` | `./scripts/verify_openclaw_capability_truth.sh` o artefacto versionado equivalente | brief corto de snapshot | apoyarse solo en docs sin verify conocida | bueno para retomes y consolidacion |
| Ticket que NO deberia usar solo status | cualquier ticket que quiera inferir delivery, browser usable, readiness total o permiso de mutacion | ninguna combinacion de docs de status alcanza por si sola | ninguna | ninguna | usar `status` para justificar acciones live | necesita otro pack y otra evidencia |

## Formato recomendado de status brief

Formato minimo recomendado para tickets y retomes:

```text
status_brief_at: 2026-04-01T23:59:59Z
repo_branch: main
repo_commit: <sha>
repo_dirty: no
primary_verify: ./scripts/verify_openclaw_capability_truth.sh
primary_verify_result: PASS|PARTIAL|BLOCKED|UNVERIFIED
canonical_docs:
- docs/CAPABILITY_MATRIX.md
- docs/CURRENT_STATE.md
- handoffs/HANDOFF_CURRENT.md
- docs/OPENCLAW_STATUS_EVIDENCE_PACK.md
status_surfaces_cited:
- openclaw gateway status
- openclaw status
- openclaw channels status --probe
executive_summary: <3-5 lineas maximo>
limitations:
- no prueba delivery real
- no prueba browser usable
- no autoriza tocar runtime
followup_boundary:
- WhatsApp sigue congelado
- browser nativo sigue fuera
```

Regla practica:

- el brief debe ser corto
- debe citar surfaces concretas
- debe incluir limitaciones explicitamente
- debe apuntar a docs canonicas en vez de reescribir todo

## Inferencias validas

Desde `status`, si es valido inferir:

- verdad operativa corta del control plane
- consistencia o inconsistencia visible entre surfaces de estado
- que existe una base seria para reentrada rapida
- que el proyecto puede hablar de snapshot actual sin improvisar

`status` combinado con capability matrix y current state si puede sugerir:

- donde estan los bloqueos mas visibles
- que surfaces siguen degradadas
- que carriles read-side siguen aceptados

## Inferencias invalidas

Desde `status`, no es valido inferir:

- delivery real
- browser usable
- readiness total del sistema
- seguridad de channels live
- permiso para tocar runtime
- permiso para reactivar WhatsApp
- permiso para abrir login real, pairing real o mensajes reales

Estas son las malas inferencias que deben bloquearse siempre:

- "status se ve bien, entonces podemos mandar por WhatsApp"
- "gateway status responde, entonces ya podemos tocar servicios"
- "channels status dice connected, entonces el canal esta listo para tickets live"
- "current state menciona PASS parciales, entonces el sistema esta totalmente listo"

## Como usar este pack para tickets futuros

Un ticket basado en `status` deberia declarar, como minimo:

- objetivo unico
- afirmacion concreta que quiere sostener o refutar
- surfaces de status citadas
- docs canonicas usadas
- verify primaria citada
- limitaciones explicitas
- kill criteria

Tickets que si nacen bien desde este pack:

- ticket de verdad operativa corta
- ticket de consistencia entre `status` y `channels status --probe`
- ticket de reentrada/documentacion de estado
- ticket que consolida snapshot versionado sin tocar runtime

Tickets que no deben nacer de este pack:

- reactivar WhatsApp
- probar browser nativo
- afirmar delivery real
- abrir channels live
- justificar mutaciones de config o services

Inputs minimos para un proximo ticket real apoyado en `status`:

- pregunta concreta
- scope exacto
- evidencia minima requerida
- verify primaria requerida
- limitaciones no negociables

## Como usar este pack para retome rapido

Retome corto recomendado:

1. leer `docs/CURRENT_STATE.md`
2. leer `handoffs/HANDOFF_CURRENT.md`
3. leer `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
4. ubicar el ultimo commit relevante con `git log --oneline -8`
5. correr `./scripts/verify_openclaw_capability_truth.sh` si hace falta una refresh read-side

Si no hace falta refresh, alcanza con:

- current state
- handoff
- status pack
- y un artefacto versionado reciente de la verify primaria

## Referencias canonicas

- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/self_check.sh`

## Veredicto operativo

La familia `status` no es una promesa de sistema total.

Si es esto:

- la mejor familia para verdad operativa corta
- una base fuerte para retomes y tickets de consistencia
- una superficie util solo si se usa con evidencia versionada y limites explicitos

Ese es el uso correcto del `OpenClaw Status Evidence Pack`.
