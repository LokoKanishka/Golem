# Current State

Fecha de actualizacion: 2026-03-31

## Rama actual

- `main`

## Ultimos commits relevantes

- `7d27730` `test: relax host describe surface profile expectations`
- `2ac5eb5` `chore: ignore local codex workspace artifacts`
- `f5e0da4` `test: add fixture-backed verify for surface_state_bundle stabilization`
- `14bb575` `chore: Ticket 3 - consolidate docs and add official verify script`
- `5ba4c82` `stabilize: deterministic normalization for surface_state_bundle; add verify script and handoff note`
- `4b3fb20` `feat: add audited host surface state bundles`
- `915c920` `feat: refine audited host contextual priorities`
- `77056f1` `feat: add fine-grained audited host fields`

## Estado general del repo

- El estado git inspeccionado para este tramo estaba limpio: `git status --short` no mostro cambios pendientes.
- La rama activa inspeccionada para este tramo es `main`.
- El repo no esta en bootstrap. El estado documentado y el README lo muestran como un sistema ya gobernado desde el carril canonico de tareas y sus wrappers operativos locales.
- La documentacion y los scripts versionados ubican hoy a Golem como un repo que gobierna:
  - tareas canonicas en `tasks/`
  - panel/API local para leer y mutar esas tareas
  - bridge local de WhatsApp sobre la misma API
  - evidencia durable y runtime controlado para handoffs y corridas de worker
  - verifies compuestos para task lane, readiness y perfiles user-facing

## Frentes validados

- Carril canonico de tareas:
  - `scripts/task_create.sh` figura como entrypoint canonico
  - `scripts/task_new.sh` queda como wrapper de compatibilidad
  - el gate oficial del carril sigue siendo `./scripts/verify_task_lane_enforcement.sh`
- Panel/API local:
  - el repo versiona `scripts/task_panel_read.sh`, `scripts/task_panel_mutate.sh`, `scripts/task_panel_http_server.py` y `scripts/task_panel_http_ctl.py`
  - `docs/PANEL_VISIBLE_SURFACE.md` deja explicitado el contrato unico sobre la API local y el smoke dedicado `./tests/smoke_panel_visible_ui.sh`
- WhatsApp como canal auxiliar:
  - `docs/WHATSAPP_RUNTIME_BRIDGE.md` documenta un runtime local endurecido con `task_whatsapp_bridge_runtime.py` y `task_whatsapp_bridge_ctl.py`
  - existen smokes dedicados para replay, hardening y servicio
- Worker/handoff auditables:
  - el repo ya no esta solo en handoff documental; tambien versiona la capa de controlled run y governance para corridas explicitas de Codex CLI
  - esa capa sigue siendo auditada y manual en el cierre, no una automatizacion de fondo
- Superficie de host describe:
  - el verify oficial liviano `bash tests/verify_official.sh` paso en este tramo
  - ese verify comprobo `py_compile` de `scripts/golem_host_describe_analyze.py`
  - tambien paso `tests/verify_surface_bundle.sh`
  - tambien paso `tests/verify_surface_bundle_fixture.py`

## Frentes abiertos

- La capa user-facing total no debe asumirse como cerrada solo por existir verifies. La propia documentacion de readiness y live journey distingue entre `PASS`, `BLOCKED` y `FAIL`.
- El trayecto real de WhatsApp sigue teniendo un limite honesto: el repo no prueba un inbound real repo-local durante smoke; el runtime se valida con replay de eventos de shape real y salida por CLI oficial.
- La capa de worker externo sigue siendo explicita y controlada, no un sistema de colas, callbacks, scheduling o cierres automaticos.
- La documentacion historica del repo conserva etapas anteriores (`V1`, `V1.5`, bootstrap, transiciones) que sirven como contexto pero no como lectura primaria del estado actual.
- El browser real del perfil `user` ya es adjuntable a nivel CDP/backend, pero `openclaw browser ...` sigue teniendo una deuda operativa: la CLI puede expirar a `45000ms` antes de que termine el `browser.request`.
- Para no bloquear trabajo user-facing por ese borde, el repo ahora versiona `./scripts/browser_cdp_tool.sh` como carril paralelo y minimo contra el Chrome vivo.

## Limites conocidos

- Los smokes integrales de host/browser no quedaron reejecutados en este tramo documental.
- El verify oficial vigente deja asentado que los smokes completos pueden requerir X11 y herramientas del host como `wmctrl` y `tesseract`.
- `openclaw/` y `state/live/` siguen apareciendo como estructura documental o evidencia local, no como runtime gobernado por Git dentro de este repo.
- `handoffs/` mezcla evidencia durable promovida con trazas runtime-only; la policy vigente sigue aclarando que no todo archivo de esa carpeta forma parte del estado durable del repo.
- No hay evidencia en este tramo para declarar cerrado un rediseño mayor de arquitectura, despliegue remoto, auth compleja o una interfaz separada adicional.
- El helper CDP directo sirve sobre un Chrome ya vivo; no resuelve por si solo el attach inicial ni reemplaza la deuda del operador `openclaw browser ...`.

## Desvios fuera del estado principal

- Los experimentos o capas que no deben leerse como nucleo operativo vigente son:
  - bootstrap historico y documentos de etapas previas
  - trazas runtime-only bajo `handoffs/`
  - placeholders/scaffolding de `openclaw/`
  - evidencia local bajo `state/live/`
- La capa de controlled run de Codex existe y esta documentada, pero no redefine el nucleo diario. El nucleo vigente sigue siendo panel/API/task lane con WhatsApp como canal auxiliar.

## Proximo retome recomendado

- Retomar desde el estado ya saneado del carril principal, no desde arquitectura abstracta ni desde bootstrap.
- El siguiente punto razonable de retome es reubicarse con:
  - `bash tests/verify_official.sh`
  - `./scripts/verify_task_lane_enforcement.sh`
  - `./scripts/verify_user_facing_readiness.sh`
  - `./scripts/verify_live_user_journey_smoke.sh`
- Despues de esa reubicacion, el siguiente tramo principal deberia enfocarse en estabilizacion operativa y verificabilidad real de los recorridos ya definidos, no en abrir nuevas superficies o reescribir el modelo.
