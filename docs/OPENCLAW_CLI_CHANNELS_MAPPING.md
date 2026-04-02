# OpenClaw CLI/Channels Mapping Pack

Fecha de actualizacion: 2026-04-01

## Proposito

Este documento convierte la baseline publica de OpenClaw CLI + channels en un mapa operativo real para Golem.

Su funcion no es repetir la baseline.
Su funcion es decir, de forma versionada:

- que significa en este repo cada familia `status`, `gateway`, `config` y `channels`
- que artefactos del repo sostienen cada familia
- que verify o checks ya existen
- que evidencia minima deberia exigirse para futuros tickets
- que usos si son validos y que usos no deben salir de este mapa

## Relacion con la baseline pack

El orden correcto de lectura ahora es:

1. `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
2. `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
3. `docs/CURRENT_STATE.md`
4. `handoffs/HANDOFF_CURRENT.md`

La baseline pack responde:

- que entra en la baseline publica de corto plazo
- que queda afuera
- que lenguaje general conviene usar

El mapping pack responde:

- a que surfaces reales del repo aterriza cada familia
- con que verify se sostiene
- con que evidencia minima deberia justificarse un ticket
- y que inferencias deben bloquearse

## Alcance

Este mapping si cubre:

- las familias `status`, `gateway`, `config` y `channels`
- la relacion entre esas familias y docs/scripts/verifies reales del repo
- el uso correcto de esas familias para tickets futuros
- los limites y congelamientos que siguen vigentes

## Fuera de alcance

Este mapping no cubre:

- runtime vivo
- mutacion de config local
- login real o pairing real de channels
- envio real por WhatsApp u otros canales
- `openclaw browser ...`
- browser sidecar como funcionalidad a extender
- workers, plugins comunitarios, APD/docencia o host control total

Condiciones congeladas vigentes:

- WhatsApp sigue congelado
- browser nativo de OpenClaw sigue fuera
- runtime vivo sigue fuera

## Que significa mapear una familia

En este repo, mapear una familia significa cerrar cinco cosas a la vez:

- para que sirve esa familia dentro de Golem
- que archivos del repo hoy la representan mejor
- que verify o check la respaldan
- que evidencia minima deberia exigirse al usarla
- que NO debe inferirse solo porque esa familia exista publicamente

La familia mas clara hoy es `status`.

La familia mas engañosa hoy es `channels`, seguida por `config`, porque ambas rozan runtime y seguridad aunque el proyecto actual no las autorice a mutar nada.

## Matriz operativa central

| Familia | purpose_in_project | repo_surfaces | canonical_docs | canonical_scripts | verify_or_check | evidence_expected | safe_use | unsafe_inference | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `status` | Fijar verdad operativa corta y snapshots de salud/consistencia | `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md`, `handoffs/HANDOFF_CURRENT.md` | `docs/CAPABILITY_MATRIX.md`, `docs/CURRENT_STATE.md` | `scripts/verify_openclaw_capability_truth.sh`, `scripts/self_check.sh` | `./scripts/verify_openclaw_capability_truth.sh` | salida de `openclaw gateway status`, `openclaw status`, `openclaw channels status --probe` o resumen versionado equivalente | tickets de verdad operativa, consistencia de estado y reentrada | que `status` pruebe delivery real, browser usable o readiness total | familia mas fuerte y menos ambigua |
| `gateway` | Anclar control plane, reachability y lectura panel-first | `docs/OPERATING_MODEL.md`, `docs/CAPABILITY_MATRIX.md`, `docs/BROWSER_HOST_CONTRACT.md`, `docs/CURRENT_STATE.md` | `docs/OPERATING_MODEL.md`, `docs/CAPABILITY_MATRIX.md` | `scripts/verify_openclaw_capability_truth.sh`, `scripts/self_check.sh` | `./scripts/verify_openclaw_capability_truth.sh` | `gateway status` con runtime/rpc, reachability HTTP del panel y alineacion con docs panel-first | tickets de observabilidad, control plane documental y relaciones panel/gateway | que comandos `start|stop|restart` autoricen tocar servicios en este tramo | familia operativa pero todavia read-side en este proyecto |
| `config` | Fijar limites, safety gates y contrato deny-by-default | `docs/WHATSAPP_SAFETY_CONTRACT.md`, `config/systemd-user/openclaw-whatsapp-kill-switch.conf`, `scripts/apply_whatsapp_fail_closed.sh` | `docs/WHATSAPP_SAFETY_CONTRACT.md`, `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md` | `scripts/apply_whatsapp_fail_closed.sh`, `scripts/verify_whatsapp_fail_closed.sh` | `./scripts/verify_whatsapp_fail_closed.sh` | safety contract vigente, templates versionados y verify fail-closed pasando | tickets documentales sobre limites, config policy y barreras tecnicas | que `config` habilite cambiar host vivo o reabrir WhatsApp | familia principalmente documental y de seguridad |
| `channels` | Traducir channels a taxonomy, routing, safety y limites de uso | `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`, `docs/WHATSAPP_SAFETY_CONTRACT.md`, `docs/WHATSAPP_RUNTIME_BRIDGE.md`, `docs/CAPABILITY_MATRIX.md` | `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`, `docs/WHATSAPP_SAFETY_CONTRACT.md` | `scripts/verify_openclaw_capability_truth.sh`, `scripts/verify_whatsapp_fail_closed.sh` | `./scripts/verify_whatsapp_fail_closed.sh` cuando un ticket toca WhatsApp; `./scripts/verify_openclaw_capability_truth.sh` solo como lectura historica de status | docs publicas + baseline + safety contract + verify de congelamiento si aparece WhatsApp | tickets de taxonomia, routing, safety y eleccion de futura superficie documental | que channels docs o `channels status` autoricen login, pairing o mensajes reales | familia util pero de alto riesgo si se interpreta de mas |

## Mapeo por familia

### `status`

Proposito en Golem:

- fijar la lectura corta de salud y consistencia
- apoyar tickets que comparan surfaces de estado contra verdad versionada

Surfaces reales del repo:

- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `scripts/verify_openclaw_capability_truth.sh`
- `scripts/self_check.sh`

Valor real:

- es la mejor familia para aterrizar la frase "que sabemos hoy"
- sirve para evitar que el proyecto vuelva a discutir intuiciones sin evidencia

No debe inferirse desde `status`:

- delivery real
- permiso para tocar canales
- browser usable
- readiness total del host

### `gateway`

Proposito en Golem:

- hablar del control plane local sin moverlo
- vincular CLI publica con panel-first y reachability real

Surfaces reales del repo:

- `docs/OPERATING_MODEL.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/BROWSER_HOST_CONTRACT.md`
- `docs/CURRENT_STATE.md`
- `scripts/verify_openclaw_capability_truth.sh`
- `scripts/self_check.sh`

Valor real:

- deja claro que el proyecto sigue OpenClaw-centered y panel-first
- permite tickets sobre observabilidad y contrato de control plane sin tocar runtime

No debe inferirse desde `gateway`:

- que corresponda usar `start|stop|restart`
- que el panel ya pruebe interaccion humana completa
- que cualquier feature ligada al gateway quede lista por existir el comando

### `config`

Proposito en Golem:

- fijar boundaries, deny-by-default y cambios prohibidos
- documentar donde la configuracion entra como contrato y no como permiso de mutacion

Surfaces reales del repo:

- `docs/WHATSAPP_SAFETY_CONTRACT.md`
- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `config/systemd-user/openclaw-whatsapp-kill-switch.conf`
- `scripts/apply_whatsapp_fail_closed.sh`
- `scripts/verify_whatsapp_fail_closed.sh`

Valor real:

- hoy `config` vale mas como family de safety que como family de cambio
- es la familia que mejor evita que un ticket documental derive en mutacion del host

No debe inferirse desde `config`:

- permiso para editar `~/.openclaw/openclaw.json`
- permiso para reactivar WhatsApp
- permiso para instalar o alterar servicios

### `channels`

Proposito en Golem:

- traducir la superficie publica de channels a una taxonomia usable para planear
- separar routing/safety/modelo comun de cualquier tentacion de operar canales reales

Surfaces reales del repo:

- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/WHATSAPP_SAFETY_CONTRACT.md`
- `docs/WHATSAPP_RUNTIME_BRIDGE.md`
- `docs/CAPABILITY_MATRIX.md`
- `scripts/verify_openclaw_capability_truth.sh`
- `scripts/verify_whatsapp_fail_closed.sh`

Valor real:

- deja hablar de channels como capa comun sin abrir login ni pairing
- sirve para tickets de taxonomia, comparacion y limites

No debe inferirse desde `channels`:

- que WhatsApp pueda reabrirse
- que `channels status` equivalga a delivery real
- que docs de channels autoricen pruebas live

## Evidencia minima por familia

| Familia | Evidencia minima suficiente para un ticket serio | Lo que NO alcanza |
| --- | --- | --- |
| `status` | `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md` + `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md` + `docs/CURRENT_STATE.md` + una salida reciente de `./scripts/verify_openclaw_capability_truth.sh` o un artefacto versionado equivalente | una frase de memoria, una sola linea de `status`, o una deduccion sin cruce con `CURRENT_STATE` |
| `gateway` | baseline + mapping + `docs/OPERATING_MODEL.md` + evidencia de `gateway status` y/o reachability del panel citada en `docs/CAPABILITY_MATRIX.md` o verify equivalente | asumir que los comandos `gateway start|stop|restart` justifican tocar servicios |
| `config` | baseline + mapping + `docs/WHATSAPP_SAFETY_CONTRACT.md` + `./scripts/verify_whatsapp_fail_closed.sh` cuando el ticket roce WhatsApp o safety gates | una referencia vaga a `config get/set` o la idea de que "hay config" |
| `channels` | baseline + mapping + `docs/WHATSAPP_SAFETY_CONTRACT.md` si aparece WhatsApp + `docs/CAPABILITY_MATRIX.md` + verify fail-closed cuando aplique | docs publicas de channels solas, `channels status` solo, o cualquier prueba live |

Regla corta:

- `status` y `gateway` aceptan evidencia read-side
- `config` y `channels` exigen barreras de safety mucho mas fuertes

## Usos permitidos y no permitidos

Usos permitidos del mapping pack:

- escribir tickets documentales o de mapping sobre `status`, `gateway`, `config` y `channels`
- elegir que verify debe acompañar un nuevo tramo
- decidir que familia da evidencia suficiente para una pregunta concreta
- trazar que docs y scripts del repo son canonicos por familia

Usos no permitidos del mapping pack:

- tocar runtime vivo
- reactivar WhatsApp
- usar `openclaw browser ...`
- abrir login real, pairing real o mensajes reales
- tratar al browser sidecar como excusa para tocar channels live
- abrir workers, plugins comunitarios o nuevos frentes de producto

Malas inferencias frecuentes que este documento bloquea:

- "si existe `channels status`, entonces ya podemos operar canales"
- "si existe `config set`, entonces corresponde mutar configuracion viva"
- "si `gateway status` pasa, entonces el panel y los channels ya estan listos para cualquier ticket"
- "si una doc publica existe, entonces la surface ya es usable en este host"

## Como escribir futuros tickets usando este mapping

Un ticket serio apoyado en este mapping deberia declarar, como minimo:

- familia principal: `status`, `gateway`, `config` o `channels`
- objetivo unico
- repo surfaces exactas que entran
- verify requerida
- evidencia minima requerida
- lo que queda explicitamente fuera
- kill criteria

Tickets que si nacen bien de este mapping:

- mapear `status` a artefactos versionados de verdad operativa
- auditar el contrato documental de `gateway` sin tocar servicios
- extender la taxonomia documental de `channels` sin abrir canales reales
- consolidar reglas de evidencia para tickets apoyados en `config` y safety

Tickets que no nacen bien de este mapping:

- reactivar WhatsApp
- volver a probar browser nativo
- hacer pairing live
- abrir workers reales
- mutar config viva o units systemd

## Referencias canonicas

Documentos:

- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/CURRENT_STATE.md`
- `handoffs/HANDOFF_CURRENT.md`
- `docs/WHATSAPP_SAFETY_CONTRACT.md`
- `docs/OPERATING_MODEL.md`

Verifies y checks:

- `./scripts/verify_openclaw_cli_channels_baseline.sh`
- `./scripts/verify_openclaw_cli_channels_mapping.sh`
- `./scripts/verify_openclaw_capability_truth.sh`
- `./scripts/verify_whatsapp_fail_closed.sh`

## Veredicto operativo

El baseline pack dice que CLI + channels es la baseline publica correcta.

El mapping pack agrega la traduccion que faltaba:

- `status` y `gateway` son familias aptas para tickets read-side y de verdad operativa
- `config` y `channels` son familias validas solo bajo limites mas estrictos y con safety contract explicito
- WhatsApp sigue congelado
- browser nativo de OpenClaw sigue fuera
- runtime vivo sigue fuera

Ese es el mapa operativo que ahora conviene usar para escribir los proximos tickets.
