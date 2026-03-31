# Handoff Current

Fecha de actualizacion: 2026-03-31

## Resumen ejecutivo

Este tramo dejo una verdad operativa mas dura que la narrativa previa.

OpenClaw hoy si funciona como gateway/control plane local con panel vivo y WhatsApp conectado. La brecha grande sigue estando en browser real y en todo lo que depende de ese browser o del stack local task API/bridge para subir a capacidades mas ambiciosas.

La conclusion util es simple:

- OC core local: si
- browser real usable: no
- helper CDP paralelo: existe, pero hoy no lee Chrome real en este host
- worker readiness real: no
- desktop read-side: si
- control host total: no

## Donde quedo el proyecto

- Rama documentada: `main`
- Estado git al iniciar la auditoria: limpio
- Documento principal nuevo: `docs/CAPABILITY_MATRIX.md`
- Verify rapido nuevo: `./scripts/verify_openclaw_capability_truth.sh`

## Lo mas importante que quedo probado

- `openclaw gateway status` dio `Runtime: running` y `RPC probe: ok`
- `curl http://127.0.0.1:18789/` sirvio la control UI correcta
- WhatsApp figura `linked/running/connected`
- `openclaw browser profiles` reconoce `user` y `openclaw`
- el plugin browser stock esta cargado
- `golem_host_perceive.sh` y `golem_host_describe.sh` funcionan de verdad en este host

## Lo mas importante que NO quedo probado

- envio WhatsApp real en este tramo
- browser nativo usable
- helper CDP vivo contra Chrome real
- worker externo listo para operar sin humo
- control host total

## Bloqueos reales vigentes

- `openclaw browser --browser-profile user` cae en timeout/`ECONNREFUSED 127.0.0.1:9222`
- `verify_browser_stack.sh --diagnosis-only` deja `navigation`, `reading` y `artifacts` en `BLOCKED`
- el profile managed `openclaw` tampoco entrega tabs ni snapshot util
- el helper CDP sigue fallando aunque se apunte al `DevToolsActivePort` del profile `user`
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
./scripts/verify_browser_stack.sh --diagnosis-only
./scripts/verify_worker_orchestration_stack.sh
```

## Que no conviene tocar primero

- No abrir plugins nuevos.
- No convertir esta pausa en expansion de features.
- No vender escritorio completo.
- No escalar workers antes de cerrar browser truth.

## Proximo tramo unico sugerido

Resolver la verdad del browser en este host.

Solo despues de eso conviene volver a discutir:

- worker externo real
- delivery mas ambicioso
- control host mas fuerte
- nuevas superficies funcionales
