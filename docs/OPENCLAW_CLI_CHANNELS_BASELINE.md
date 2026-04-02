# OpenClaw CLI + Channels Public Baseline

Fecha de actualizacion: 2026-04-01

## Proposito

Este documento fija la baseline publica y operativa que Golem debe usar para planear los proximos tramos alrededor de OpenClaw CLI + channels.

No es un manual total de OpenClaw.
No es un contrato de runtime vivo.
No es una reapertura del browser nativo ni de WhatsApp.

Su funcion es mas acotada:

- dar un lenguaje comun y versionado para hablar de CLI + channels
- separar lo publicamente util para planificacion de lo que solo existe como superficie de referencia
- dejar claro que entra y que no entra en los proximos tickets
- reducir reentrada y evitar volver a inflar lo que OpenClaw "deberia" hacer

## Alcance

Esta baseline si cubre:

- la CLI publica de OpenClaw como superficie de planeamiento
- los grupos de comandos CLI que sirven para estado, config, gateway, channels, logs, security y doctor
- la documentacion publica de channels como superficie de modelo operativo y de limites
- la idea publica de que los channels cuelgan del Gateway y comparten una capa comun de operaciones
- la relacion entre esa superficie publica y el estado real versionado de Golem
- el lenguaje que deberian usar futuros tickets cuando se apoyen en CLI + channels

## Fuera de alcance

Esta baseline no cubre:

- runtime vivo
- cambios de config local
- login real en channels
- pairing real
- envio de mensajes reales
- WhatsApp operativo
- browser nativo de OpenClaw
- workers, MCP, Codex real o plugins comunitarios
- APD/docencia, host control total o nuevas features

Condiciones congeladas que siguen vigentes:

- WhatsApp sigue congelado y fuera de alcance
- `openclaw browser ...` sigue fuera de la baseline usable
- el carril browser aceptado sigue siendo el browser sidecar versionado del repo

## Fuentes publicas elegidas

Fuentes publicas minimas y defendibles para esta baseline:

- `https://docs.openclaw.ai/cli`
- `https://docs.openclaw.ai/channels`

Fuentes del repo que aterrizan esa lectura al estado real de Golem:

- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `docs/BROWSER_SIDECAR_RUNBOOK.md`
- `docs/WHATSAPP_SAFETY_CONTRACT.md`
- `handoffs/HANDOFF_CURRENT.md`
- `outbox/manual/20260402T011245Z_recommend-openclaw-public-baseline_recommendation.md`

No usamos como baseline principal:

- docs publicas de browser nativo
- docs de plugins como superficie principal
- runtime local como "prueba" de lo publico

Esas superficies quedan como follow-on o referencia, no como base de planeamiento inmediato.

## Superficies CLI clave

La CLI publica si ofrece una base util para planificar porque expone, al menos, estas familias:

- estado y salud:
  - `status`
  - `health`
  - `sessions`
  - `logs`
  - `doctor`
- gateway y operacion:
  - `gateway health`
  - `gateway status`
  - `gateway probe`
  - `gateway start|stop|restart|run`
- config y seguridad:
  - `configure`
  - `config get|set|unset|file|validate`
  - `security`
  - `secrets`
- channels:
  - `channels list`
  - `channels status`
  - `channels logs`
  - `channels add|remove`
  - `channels login|logout`

Lo util de esta superficie no es "ejecutarla ahora".
Lo util es que deja un vocabulario operativo acotado para futuros tickets:

- estado observable
- config declarable
- gateway como plano comun
- channels como capa administrable por CLI

## Superficies Channels clave

La documentacion publica de channels entra en la baseline por cuatro razones:

- deja claro que cada channel conecta via Gateway
- deja claro que texto existe como minimo comun y que media/reactions varian
- deja claro que hay una operacion multi-channel con routing por chat
- deja visibles las dependencias y diferencias por channel sin vender uniformidad falsa

Para planificacion, las superficies channels que si importan son:

- overview de channels como capa comun sobre Gateway
- lista publica de channels soportados
- notas publicas sobre routing, groups, troubleshooting y seguridad
- existencia de pairing y allowlists como limites de seguridad, no como flujo a ejecutar en este tramo

La baseline no necesita catalogar cada channel en profundidad.
Necesita usar la familia channels para planear con lenguaje honesto:

- surface comun
- diferencias por implementacion
- safety gates
- costos de setup y estado en disco

## Inventario minimo usable

### Baseline core

| Superficie | Tipo | Para que entra |
| --- | --- | --- |
| CLI reference | Public doc | Vocabulario operativo y familias de comando |
| `status`, `health`, `sessions`, `logs`, `doctor` | CLI core | Estado, salud y observabilidad |
| `gateway *` | CLI ops | Plano comun de operacion |
| `config *`, `configure`, `security`, `secrets` | CLI config | Modelo de configuracion y safety |
| `channels *` | CLI channels | Operaciones y lifecycle de channels |
| Channels overview | Public doc | Modelo comun de Gateway + channels |
| Channels notes | Public doc | Routing, safety, troubleshooting, diferencias |

### Referencia util pero no baseline principal

| Superficie | Tipo | Como tratarla |
| --- | --- | --- |
| Browser docs publicas | Public doc | Referencia separada; no baseline principal |
| Plugin docs | Public doc | Follow-on cuando haya tranche de extensibilidad |
| Channel-specific pages | Public doc | Consultar solo si un ticket ya eligio channel |

### Explicitamente afuera

| Superficie | Motivo de exclusion |
| --- | --- |
| WhatsApp runtime | Sigue congelado por politica de seguridad |
| Pairing live | Riesgo alto y fuera del baseline documental |
| `openclaw browser ...` | Browser nativo bloqueado como superficie usable |
| Workers/MCP/Codex real | No forman parte de esta baseline publica |
| Servicios locales y config viva | Este tramo no modifica runtime |

## Matriz de utilidad y madurez

| Superficie | Tipo | Utilidad para planificacion | Madurez percibida | Dependencia de runtime | Riesgo de mala interpretacion | Uso recomendado | No uso recomendado | Evidencia base |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CLI reference general | Public doc | Alta | Alta | Baja | Media | Definir lenguaje comun y familias de comando | Tratarla como prueba de readiness local | `docs.openclaw.ai/cli` |
| `gateway *` | CLI family | Alta | Alta | Media | Media | Planear observabilidad y control plane local | Asumir que start/stop documentado implica que debamos tocar runtime ahora | `docs.openclaw.ai/cli` |
| `channels *` | CLI family | Alta | Alta | Media | Alta | Delimitar lifecycle de channels y tickets futuros | Ejecutar login/pairing reales desde esta baseline | `docs.openclaw.ai/cli` |
| Channels overview + notes | Public doc | Alta | Media | Baja | Alta | Entender modelo comun, routing y safety | Inferir uniformidad total entre channels | `docs.openclaw.ai/channels` |
| Channel-specific pages | Public doc | Media | Media | Media | Alta | Consultarlas solo cuando un ticket ya eligio un channel | Convertirlas en baseline global del proyecto | `docs.openclaw.ai/channels/*` |
| Browser docs | Public doc | Baja para este pack | Media | Alta | Muy alta | Mantenerlas congeladas salvo tranche separado | Reabrir browser nativo por reflejo | `docs.openclaw.ai/tools/browser` |
| Plugin docs | Public doc | Baja para este pack | Media | Media | Media | Usarlas solo en tramos de extension | Mezclar extensibilidad con baseline operacional | `docs.openclaw.ai/tools/plugin` |

## Relacion con el estado real de Golem

Esta baseline no reemplaza la verdad local ya versionada.
La aterriza.

El estado real del repo hoy obliga a leer CLI + channels con estas correcciones:

- OpenClaw core local existe como gateway/control plane observado por CLI
- el browser nativo sigue degradado y no debe usarse como base de planificacion
- el browser sidecar es el unico carril browser aceptado
- WhatsApp sigue fuera de alcance y congelado por contrato de seguridad
- el proyecto ya tiene lanes de dossier, decision, recommendation, prioritization y execution tranche para decidir que hacer sin tocar runtime

Por eso esta baseline sirve para planear alrededor de OpenClaw sin volver a vender:

- browser nativo como listo
- channels live como seguros por defecto
- workers como ya resueltos

## Limites y advertencias

Esta baseline si permite decir:

- "el proyecto puede planear usando la CLI publica como contrato de lenguaje"
- "channels es una familia comun apoyada en Gateway"
- "hay operaciones publicas de estado, config y lifecycle"
- "hay diferencias y safety gates por channel"

Esta baseline no permite decir:

- "WhatsApp ya esta listo para volver"
- "la doc publica prueba que el runtime local esta sano para cualquier channel"
- "el browser nativo volvio a ser una superficie aceptada"
- "pairing, access o login deben entrar en el siguiente tramo"
- "cada channel es equivalente o igual de barato de operar"

## Como usar esta baseline para futuros tickets

Un ticket futuro si puede nacer de esta baseline cuando:

- necesita definir lenguaje y artefactos sobre CLI + channels sin tocar runtime
- quiere mapear una familia de comandos relevante a una necesidad del proyecto
- quiere acotar un tranche documental u operacional ligero alrededor de config, estado, observabilidad o routing
- necesita elegir que parte de channels merece un tranche especifico posterior

Un ticket futuro no deberia nacer de esta baseline cuando:

- depende de reactivar WhatsApp
- depende de browser nativo
- requiere login real, pairing real o mensajes reales
- requiere workers o plugins nuevos para demostrar valor
- mezcla demasiados frentes sin una frontera tecnica clara

Inputs minimos para el proximo ticket real:

- objetivo unico
- superficie CLI/channels exacta que entra
- que queda congelado
- artefactos requeridos
- verify esperada
- kill criteria

## Ticket seeds razonables

Tickets que si nacen bien desde esta baseline:

- tranche de mapa versionado de comandos CLI de estado/config/gateway relevantes para Golem
- tranche de taxonomia de channels por costo operativo, safety gate y dependencia externa
- tranche de relacion entre `channels *` y artefactos/versionado del repo
- tranche de criterios para elegir un channel objetivo sin tocar runtime vivo

Tickets que no deberian salir de esta baseline:

- "reactivar WhatsApp"
- "volver a probar browser nativo"
- "hacer pairing live"
- "abrir workers reales"
- "integrar todo el ecosistema de plugins"

## Checks recomendados

Checks minimos antes de usar esta baseline como soporte de otro tramo:

- leer `docs/CURRENT_STATE.md`
- leer `handoffs/HANDOFF_CURRENT.md`
- confirmar que `docs/WHATSAPP_SAFETY_CONTRACT.md` sigue vigente
- correr `./scripts/verify_openclaw_cli_channels_baseline.sh`

Si el tramo futuro toca browser, la baseline sola no alcanza.
Debe pasar por el carril sidecar aceptado y por su evidencia propia.

## Veredicto operativo

La baseline publica usable de corto plazo para Golem no es "todo OpenClaw".

Es esto:

- CLI publica como contrato de lenguaje y familias de operacion
- channels como modelo comun apoyado en Gateway
- safety y limits explicitos
- browser nativo fuera
- WhatsApp congelado
- runtime vivo fuera

Ese es el baseline pack sobre el que conviene escribir los proximos tickets.
