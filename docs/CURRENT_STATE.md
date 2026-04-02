# Current State

Fecha de actualizacion: 2026-04-01

## Estado critico vigente

La verdad anterior sobre "WhatsApp conectado y sano" queda suspendida por un incidente grave detectado el 2026-04-01.

- se observo un mensaje real de control/pairing de OpenClaw en un chat personal de WhatsApp
- eso demuestra un camino de salida real desde el gateway hacia conversaciones personales
- el estado vigente ya no es "WhatsApp operativo"
- el estado vigente es `WHATSAPP CONGELADO`

Hasta nuevo verify:

- `openclaw-gateway.service`, `openclaw-direct-chat.service` y `fusion-total-direct-chat.service` deben permanecer detenidos
- el kill switch persistente via `ConditionPathExists` debe seguir activo
- la config viva debe mantener `channels.whatsapp.enabled=false`
- pairing/access/debug para WhatsApp deben quedar en sink local, nunca en outbound real

Documento rector de este frente:

- `docs/WHATSAPP_SAFETY_CONTRACT.md`

Verify obligatorio de este frente:

- `./scripts/verify_whatsapp_fail_closed.sh`

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
- El browser nativo no esta operativo como superficie confiable de trabajo y queda degradado a deuda.
- El helper CDP existe como carril paralelo versionado; sobre el Chrome ambient actual sigue bloqueado, pero sobre un Chrome sidecar dedicado si logra `tabs/snapshot/find`.
- El browser sidecar ya tiene lifecycle y wrappers operativos estables para uso cotidiano.
- El browser sidecar ya quedo probado tambien sobre web publica real simple.
- El browser sidecar ya quedo elevado a un carril de lectura estructurada y comparacion basica sobre web publica real.
- El browser sidecar ya quedo elevado tambien a un dossier lane declarativo para tareas chicas de investigacion publica multi-fuente.
- El browser sidecar ya quedo elevado tambien a un decision lane declarativo para preguntas publicas concretas con matriz y veredicto rastreable.
- El browser sidecar ya quedo elevado tambien a un recommendation lane declarativo para recomendaciones practicas con alternativas, riesgos, precondiciones y siguiente paso.
- El browser sidecar ya quedo elevado tambien a un project prioritization lane declarativo para frentes del proyecto con buckets NOW/NEXT/LATER/FROZEN/DO_NOT_TOUCH/REOPEN_ONLY_IF.
- El browser sidecar ya quedo elevado tambien a un execution tranche lane declarativo para elegir un unico tramo ejecutable con winner, runner-up, alcance, verify y kill criteria.
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
- aun cuando existe un listener raw vivo en `9222`, `openclaw browser ...` sigue fallando con `Unexpected server response: 404` o timeout
- `./scripts/verify_browser_stack.sh --diagnosis-only` clasifico `navigation`, `reading` y `artifacts` como `BLOCKED`.
- El profile managed `openclaw` tampoco salva el frente:
  - `tabs` devuelve `No tabs`
  - `snapshot` cae con `Missing X server or $DISPLAY`
- `./scripts/browser_cdp_tool.sh` contra el Chrome ambient actual queda bloqueado:
  - sin env extra devuelve `ERROR: fetch failed`
  - aun apuntando al `DevToolsActivePort` real del profile `user`, `curl 127.0.0.1:9222/json/list` falla
- `./scripts/verify_browser_capability_truth.sh` si deja un carril browser en `PASS`:
  - levanta una proof page local
  - levanta un Chrome dedicado con `--headless=new --no-sandbox --remote-debugging-port=9222`
  - prueba `tabs`, `snapshot` y `find` via `browser_cdp_tool.sh`
- `./scripts/verify_browser_sidecar_operational.sh` deja una verify corta y reusable del carril operativo:
  - arranca el sidecar si hace falta
  - levanta una pagina local de prueba
  - prueba `open`, `tabs`, `snapshot` y `find`
- `./scripts/verify_browser_sidecar_real_web.sh` deja una verify real del carril:
  - usa un runtime sidecar aislado y temporal
  - abre `https://www.iana.org/domains/reserved`
  - abre `https://www.rfc-editor.org/rfc/rfc2606.html`
  - prueba `tabs`, seleccion por titulo/url/indice, `read` y `find`
- `./scripts/browser_sidecar_select.sh` ya deja seleccion explicita por indice, titulo parcial o URL parcial y falla si el selector es ambiguo
- `./scripts/browser_sidecar_read.sh` ya deja una lectura directa de una tab real sin obligar a recordar que `snapshot` funciona como lectura
- `./scripts/browser_sidecar_extract.sh` ya deja una salida estructurada y normalizada:
  - metadata minima
  - texto visible normalizado
  - links
  - output en `markdown` o `json`
  - guardado opcional en `outbox/manual/`
- `./scripts/browser_sidecar_compare.sh` ya deja una comparacion operativa entre dos paginas reales:
  - resumen
  - excerpts
  - diferencias exclusivas por target
  - conclusion simple
  - artefactos `markdown` y `json`
- `./scripts/verify_browser_sidecar_comparison_lane.sh` ya deja un verify de punta a punta:
  - open
  - tabs
  - select
  - extract
  - find
  - compare
  - artefactos comparativos
- `browser_tasks/*.json` ya deja tareas declarativas con:
  - `task_id`, `title`, `description`
  - `sources`
  - `focus_terms`
  - `expected_signals`
  - `comparisons`
- `./scripts/browser_sidecar_dossier_run.sh` ya deja un pipeline multi-fuente:
  - carga la tarea
  - abre y resuelve fuentes reales
  - extrae cada fuente
  - aplica foco explicito
  - compara pares declarados
  - genera un dossier final con artefactos trazables
- `./scripts/verify_browser_sidecar_dossier_lane.sh` ya deja una verify larga reusable del dossier lane
- `./scripts/browser_sidecar_decision_run.sh` ya deja una capa de decision publica:
  - carga una pregunta concreta
  - evalua criterios con pesos simples
  - junta evidencia por criterio
  - produce source ranking, matriz y veredicto final
- `browser_tasks/decision-*.json` ya deja tareas declarativas de decision:
  - `question`
  - `decision_criteria`
  - `weight`
  - `evidence_terms`
- `./scripts/verify_browser_sidecar_decision_lane.sh` ya deja una verify larga reusable del decision lane
- `./scripts/browser_sidecar_recommendation_run.sh` ya deja una capa de recomendacion publica:
  - reutiliza el decision lane base
  - evalua alternativas explicitas
  - expone riesgos, precondiciones y costo relativo
  - produce recommendation matrix, runner-up y siguiente paso sugerido
- `browser_tasks/recommend-*.json` ya deja tareas declarativas de recommendation:
  - `alternatives`
  - `relative_cost`
  - `risk_hints`
  - `preconditions`
  - `suggested_next_step`
- `./scripts/verify_browser_sidecar_recommendation_lane.sh` ya deja una verify larga reusable del recommendation lane
- `./scripts/browser_sidecar_prioritization_run.sh` ya deja una capa de priorizacion de proyecto:
  - mezcla evidencia publica y evidencia local versionada
  - evalua frentes explicitos del proyecto
  - asigna buckets NOW/NEXT/LATER/FROZEN/DO_NOT_TOUCH/REOPEN_ONLY_IF
  - expone riesgos, precondiciones, kill criteria y siguiente tramo sugerido
- `browser_tasks/prioritize-*.json` ya deja tasks declarativas de priorizacion:
  - `project_fronts`
  - `priority_buckets`
  - `local_sources`
  - `kill_criteria`
- `./scripts/verify_browser_sidecar_prioritization_lane.sh` ya deja una verify larga reusable del prioritization lane
- `./scripts/browser_sidecar_execution_tranche_run.sh` ya deja una capa de seleccion de tramo ejecutable:
  - consume un `prioritization_task` upstream
  - evalua `candidate_tranches` explicitos
  - deja ganador, runner-up y matriz final
  - produce un execution brief en `json` y `md`
- `browser_tasks/tranche-*.json` ya deja tasks declarativas de execution tranche:
  - `candidate_tranches`
  - `in_scope`
  - `out_of_scope`
  - `acceptance_criteria`
  - `verify_requirements`
  - `kill_criteria`
  - `implementation_ticket_seed`
- `./scripts/verify_browser_sidecar_execution_tranche_lane.sh` ya deja una verify larga reusable del execution tranche lane
- la task `browser_tasks/tranche-golem-openclaw-next-execution.json` ya produjo un ganador real:
  - `gateway_channels_public_baseline_pack`
  - runner-up: `truth_surface_reentry_refresh`
- la task `browser_tasks/tranche-project-evidence-maintenance-next-execution.json` ya produjo un ganador real:
  - `truth_surface_refresh_pack`
  - runner-up: `artifact_index_and_retome_pack`
- `./scripts/verify_worker_orchestration_stack.sh` no paso:
  - los verifies canonicos del stack worker fallaron
  - el self-check previo ya marcaba `browser_relay FAIL`, `task_api FAIL` y `whatsapp_bridge_service FAIL`
  - el chain execution audit ademas detecto drift en pasos planificados vs root terminal

## Lo que no corresponde inflar

- Chrome abierto como proceso no significa browser usable.
- Browser plugin cargado no significa lectura de paginas reales.
- `DevToolsActivePort` presente no significa endpoint CDP realmente vivo.
- Un listener raw vivo tampoco significa que `openclaw browser ...` sepa usarlo.
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
  - `scripts/browser_cdp_tool.sh` cuando controla un Chrome sidecar dedicado
  - `scripts/browser_sidecar_start.sh`, `scripts/browser_sidecar_status.sh`, `scripts/browser_sidecar_stop.sh`
  - `scripts/browser_sidecar_open.sh`, `scripts/browser_sidecar_tabs.sh`, `scripts/browser_sidecar_select.sh`
  - `scripts/browser_sidecar_read.sh`, `scripts/browser_sidecar_snapshot.sh`, `scripts/browser_sidecar_find.sh`
  - `scripts/browser_sidecar_extract.sh`, `scripts/browser_sidecar_compare.sh`
  - `scripts/browser_sidecar_dossier_run.sh`
  - `scripts/browser_sidecar_decision_run.sh`
  - `scripts/browser_sidecar_recommendation_run.sh`
  - `scripts/browser_sidecar_prioritization_run.sh`
  - `scripts/browser_sidecar_execution_tranche_run.sh`
  - `scripts/verify_browser_capability_truth.sh` como smoke/browser truth oficial del carril aceptado
  - `scripts/verify_browser_sidecar_operational.sh` como verify corta del carril operativo
  - `scripts/verify_browser_sidecar_real_web.sh` como verify real sobre web publica simple
  - `scripts/verify_browser_sidecar_comparison_lane.sh` como verify larga del carril de lectura/comparacion
  - `scripts/verify_browser_sidecar_dossier_lane.sh` como verify larga del carril de dossier declarativo
  - `scripts/verify_browser_sidecar_decision_lane.sh` como verify larga del carril de decision declarativa
  - `scripts/verify_browser_sidecar_recommendation_lane.sh` como verify larga del carril de recommendation declarativa
  - `scripts/verify_browser_sidecar_prioritization_lane.sh` como verify larga del carril de project prioritization declarativa
  - `scripts/verify_browser_sidecar_execution_tranche_lane.sh` como verify larga del carril de execution tranche declarativa
  - `scripts/golem_host_perceive.sh`
  - `scripts/golem_host_describe.sh`
  - governance/controlled-run de worker como capa subordinada, no nucleo

## Documento principal de esta verdad

- `docs/CAPABILITY_MATRIX.md`
- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
- `docs/BROWSER_SIDECAR_RUNBOOK.md`
- `docs/BROWSER_DOSSIER_LANE.md`
- `docs/BROWSER_DECISION_LANE.md`
- `docs/BROWSER_RECOMMENDATION_LANE.md`
- `docs/BROWSER_PROJECT_PRIORITIZATION_LANE.md`
- `docs/BROWSER_EXECUTION_TRANCHE_LANE.md`

## Retome recomendado

El siguiente retome razonable ya no es "descubrir" la verdad del browser ni rediscutir el carril aceptado.

Eso ya quedo resuelto:

- camino aceptado hoy: Chrome sidecar dedicado + wrappers `browser_sidecar_*`
- deuda explicita: browser nativo de OC
- baseline publica nueva para planear CLI + channels sin tocar runtime: `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- verify ligera nueva del baseline pack: `./scripts/verify_openclaw_cli_channels_baseline.sh`
- mapping pack nuevo para aterrizar `status`, `gateway`, `config` y `channels` a surfaces reales del repo: `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
- verify ligera nueva del mapping pack: `./scripts/verify_openclaw_cli_channels_mapping.sh`
- WhatsApp sigue congelado y fuera de esta baseline

El siguiente tramo razonable pasa a ser uno solo:

- usar `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md` junto con `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md` para escribir los proximos tickets sobre `status`, `gateway`, `config` y `channels`, sin reabrir browser nativo, workers, host control ni WhatsApp
