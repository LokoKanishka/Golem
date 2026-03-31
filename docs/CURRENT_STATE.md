# Current State

Fecha de actualizacion: 2026-03-31

## Rama y baseline

- Rama auditada: `main`
- Estado git al iniciar el tramo: limpio
- OpenClaw auditado: `2026.3.28 (f9b1079)`
- Gateway auditado: `127.0.0.1:18789`

## Verdad operativa corta

La lectura honesta del host hoy es:

- OpenClaw si esta sano como gateway/control plane local.
- El panel web/control UI si esta servido y alcanzable.
- WhatsApp si figura conectado y coherente a nivel de salud general.
- El browser nativo no esta operativo como superficie confiable de trabajo.
- El helper CDP existe como carril paralelo versionado, pero hoy no puede leer Chrome real en este host.
- La percepcion/descripcion read-side del desktop si existe y produce evidencia real.
- La readiness real de worker externo no alcanza hoy para venderse como capacidad operativa estable.

## Lo que si quedo probado en este tramo

- `openclaw gateway status` devolvio `Runtime: running` y `RPC probe: ok`.
- `curl http://127.0.0.1:18789/` sirvio HTML del panel con `<title>OpenClaw Control</title>`.
- `openclaw status` y `openclaw channels status --probe` coincidieron en que WhatsApp esta `linked/running/connected`.
- `openclaw plugins list` mostro `browser` y `whatsapp` cargados.
- `openclaw browser profiles` mostro los profiles `user` y `openclaw`.
- `./scripts/golem_host_perceive.sh json` produjo screenshots y contexto de ventanas.
- `./scripts/golem_host_describe.sh active-window --json` produjo `surface_state_bundle` y clasificacion semantica de la ventana activa.

## Lo que quedo bloqueado o degradado

- `openclaw browser --browser-profile user status/tabs/snapshot` no queda usable hoy:
  - falla con `ECONNREFUSED 127.0.0.1:9222`
  - o expira esperando tabs disponibles
- `./scripts/verify_browser_stack.sh --diagnosis-only` clasifico `navigation`, `reading` y `artifacts` como `BLOCKED`.
- El profile managed `openclaw` tampoco salva el frente:
  - `tabs` devuelve `No tabs`
  - `snapshot` cae con `Missing X server or $DISPLAY`
- `./scripts/browser_cdp_tool.sh` hoy tambien queda bloqueado:
  - sin env extra devuelve `ERROR: fetch failed`
  - aun apuntando al `DevToolsActivePort` real del profile `user`, `curl 127.0.0.1:9222/json/list` falla
- `./scripts/verify_worker_orchestration_stack.sh` no paso:
  - los verifies canonicos del stack worker fallaron
  - el self-check previo ya marcaba `browser_relay FAIL`, `task_api FAIL` y `whatsapp_bridge_service FAIL`
  - el chain execution audit ademas detecto drift en pasos planificados vs root terminal

## Lo que no corresponde inflar

- Chrome abierto como proceso no significa browser usable.
- Browser plugin cargado no significa lectura de paginas reales.
- `DevToolsActivePort` presente no significa endpoint CDP realmente vivo.
- Governance/documentacion de worker no significa worker externo listo para operar hoy.
- Read-side del desktop no significa control host total.
- WhatsApp conectado no significa delivery real probado en este tramo.

## Carriles vigentes

- Nucleo OC real:
  - gateway local
  - panel/control UI
  - sesiones y estado por CLI
  - WhatsApp conectado
- Carriles paralelos aceptados:
  - `scripts/browser_cdp_tool.sh` como sidecar browser condicionado a endpoint real
  - `scripts/golem_host_perceive.sh`
  - `scripts/golem_host_describe.sh`
  - governance/controlled-run de worker como capa subordinada, no nucleo

## Documento principal de esta verdad

- `docs/CAPABILITY_MATRIX.md`

## Retome recomendado

El siguiente retome razonable ya no es “seguir agregando cosas”.

Es uno solo:

- cerrar la verdad del browser en este host

Eso significa elegir y demostrar un unico camino reproducible para:

- obtener tabs reales
- leer una pagina real
- dejar evidencia corta y repetible

Antes de eso no conviene abrir:

- plugins nuevos
- mas automation de workers
- promesas de control host total
- nuevas features browser
