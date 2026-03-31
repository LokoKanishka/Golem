# Handoff Current

Fecha de actualizacion: 2026-03-30

## Resumen ejecutivo

Golem queda hoy documentado en `main` como un sistema ya fuera de bootstrap, con carril canonico de tareas gobernado desde el repo, panel/API local como contrato principal y WhatsApp como canal auxiliar sobre el mismo backend local. El repo estaba limpio al iniciar este tramo documental y no se detectaron cambios pendientes sin commit que obligaran a reinterpretar el estado.

La documentacion versionada y los scripts vigentes muestran cuatro capas reales: task lane canonico, superficie local del panel, bridge/runtime local de WhatsApp y capa auditada de handoff/worker runs. El verify oficial liviano paso en este tramo y la actividad reciente de commits se concentra en la estabilizacion de `surface_state_bundle`, no en un rediseño del nucleo.

## Donde quedo el proyecto

- Rama actual documentada: `main`
- Estado git al iniciar este handoff: limpio
- Nucleo vigente:
  - panel/gateway como consola principal
  - API local unica sobre tareas canonicas
  - panel visible y WhatsApp reutilizando ese mismo contrato
- Estado reciente mas visible:
  - consolidacion documental previa
  - verify oficial liviano agregado
  - estabilizacion de `surface_state_bundle` con verify por fixture

## Que no tocar primero

- No reabrir bootstrap ni reescribir la arquitectura desde cero.
- No tratar a WhatsApp como sesion principal.
- No convertir la capa de worker externo en el nuevo centro del sistema.
- No mezclar trazas runtime-only o placeholders historicos con el estado principal del proyecto.

## Que revisar primero al volver

- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/OPERATING_MODEL.md`
- `docs/WHATSAPP_RUNTIME_BRIDGE.md`
- `docs/PANEL_VISIBLE_SURFACE.md`
- `docs/CAPABILITY_VERIFICATION_MATRIX.md`

## Comandos utiles para reubicarse rapido

```bash
git status --short
git branch --show-current
git log --oneline -8
bash tests/verify_official.sh
./scripts/verify_task_lane_enforcement.sh
./scripts/verify_user_facing_readiness.sh
./scripts/verify_live_user_journey_smoke.sh
```

Notas:

- `tests/verify_official.sh` es la reubicacion rapida mas barata para el frente reciente de `surface_state_bundle`.
- Los verifies mas pesados pueden depender de X11 y utilidades del host.
- La documentacion de readiness ya distingue `PASS`, `BLOCKED` y `FAIL`; no inflar `BLOCKED` a cierre.

## Limites y bloqueos que siguen vigentes

- Los smokes integrales de host/browser no quedaron reejecutados en este tramo.
- El inbound real de WhatsApp no se prueba repo-localmente en smoke; el bridge se valida con replay de eventos de shape real y salida por CLI oficial.
- La capa de Codex controlled run sigue siendo auditada y explicita, no automatizacion completa.
- `openclaw/` y `state/live/` siguen fuera del nucleo versionado como runtime gobernado por este repo.

## Proximo tramo unico sugerido

El proximo tramo recomendado, despues de esta pausa o desviacion, es retomar desde verificabilidad y operacion real del nucleo ya definido:

- reubicarse con los verifies oficiales
- confirmar si los recorridos `user-facing` y `live user journey` permanecen en el mismo estado real
- trabajar sobre estabilizacion operativa del sistema vigente

No corresponde abrir primero una nueva feature, una segunda arquitectura ni una automatizacion adicional de workers.
