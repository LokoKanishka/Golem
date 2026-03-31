# Handoff Current

Fecha de actualizacion: 2026-03-31

## Resumen ejecutivo

Este tramo dejo una verdad operativa mas dura que la narrativa previa.

OpenClaw hoy si funciona como gateway/control plane local con panel vivo y WhatsApp conectado. La brecha grande ya no esta difusa: el browser nativo de OC queda degradado a deuda, y el unico camino browser que hoy queda en `PASS` es un sidecar Chrome dedicado consumido por `browser_cdp_tool.sh`.

La conclusion util es simple:

- OC core local: si
- browser real usable por OC nativo: no
- helper CDP paralelo sobre Chrome ambient: no
- helper CDP paralelo sobre Chrome sidecar dedicado: si
- worker readiness real: no
- desktop read-side: si
- control host total: no

Ese veredicto ya no queda solo en un smoke de verdad. El carril browser aceptado ahora tiene interfaz operativa estable:

- `./scripts/browser_sidecar_start.sh`
- `./scripts/browser_sidecar_status.sh`
- `./scripts/browser_sidecar_stop.sh`
- `./scripts/browser_sidecar_open.sh`
- `./scripts/browser_sidecar_tabs.sh`
- `./scripts/browser_sidecar_select.sh`
- `./scripts/browser_sidecar_read.sh`
- `./scripts/browser_sidecar_snapshot.sh`
- `./scripts/browser_sidecar_find.sh`
- `./scripts/verify_browser_sidecar_operational.sh`
- `./scripts/verify_browser_sidecar_real_web.sh`

## Donde quedo el proyecto

- Rama documentada: `main`
- Estado git al iniciar la auditoria: limpio
- Documento principal nuevo: `docs/CAPABILITY_MATRIX.md`
- Verify rapido nuevo: `./scripts/verify_openclaw_capability_truth.sh`
- Runbook browser nuevo: `docs/BROWSER_SIDECAR_RUNBOOK.md`

## Lo mas importante que quedo probado

- `openclaw gateway status` dio `Runtime: running` y `RPC probe: ok`
- `curl http://127.0.0.1:18789/` sirvio la control UI correcta
- WhatsApp figura `linked/running/connected`
- `openclaw browser profiles` reconoce `user` y `openclaw`
- el plugin browser stock esta cargado
- `golem_host_perceive.sh` y `golem_host_describe.sh` funcionan de verdad en este host
- `verify_browser_capability_truth.sh` deja `tabs/snapshot/find` en `PASS` via sidecar dedicado
- `verify_browser_sidecar_operational.sh` deja un smoke corto reusable para start/status/open/tabs/snapshot/find
- `verify_browser_sidecar_real_web.sh` deja `PASS` sobre dos targets publicos reales y estables:
  - `https://www.iana.org/domains/reserved`
  - `https://www.rfc-editor.org/rfc/rfc2606.html`
- la seleccion de tabs ya no queda ambigua:
  - `browser_sidecar_select.sh` acepta indice, titulo parcial o URL parcial
  - si hay multiples matches, falla y los lista

## Lo mas importante que NO quedo probado

- envio WhatsApp real en este tramo
- browser nativo usable
- worker externo listo para operar sin humo
- control host total

## Bloqueos reales vigentes

- `openclaw browser --browser-profile user` cae en timeout/`ECONNREFUSED 127.0.0.1:9222`
- `verify_browser_stack.sh --diagnosis-only` deja `navigation`, `reading` y `artifacts` en `BLOCKED`
- el profile managed `openclaw` tampoco entrega tabs ni snapshot util
- aun con un listener raw vivo en `9222`, `openclaw browser ...` devuelve `Unexpected server response: 404` o timeout
- el helper CDP sigue fallando sobre el Chrome ambient aunque se apunte al `DevToolsActivePort` del profile `user`
- `verify_worker_orchestration_stack.sh` falla porque el self-check previo marca browser relay/task API/bridge no operativos y el chain audit detecta drift

## Que revisar primero al volver

- `README.md`
- `docs/OPERATING_MODEL.md`
- `docs/CURRENT_STATE.md`
- `docs/CAPABILITY_MATRIX.md`
- `docs/BROWSER_HOST_CONTRACT.md`

## Comandos utiles para reubicarse rapido

```bash
git status --short
git branch --show-current
git log --oneline -8
./scripts/verify_openclaw_capability_truth.sh
./scripts/verify_browser_capability_truth.sh
./scripts/browser_sidecar_status.sh
./scripts/verify_browser_sidecar_operational.sh
./scripts/verify_browser_sidecar_real_web.sh
./scripts/verify_browser_stack.sh --diagnosis-only
./scripts/verify_worker_orchestration_stack.sh
```

## Que no conviene tocar primero

- No abrir plugins nuevos.
- No convertir esta pausa en expansion de features.
- No vender escritorio completo.
- No escalar workers antes de cerrar browser truth.

## Proximo tramo unico sugerido

Usar el carril browser sidecar ya probado sobre web publica real en una tarea de lectura/navegacion concreta, sin reabrir browser nativo ni abrir workers/control host.

No corresponde volver a discutir antes de eso:

- worker externo real
- delivery mas ambicioso
- control host mas fuerte
- nuevas superficies funcionales
