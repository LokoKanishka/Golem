# Handoff Current

Fecha de actualizacion: 2026-04-02

## Incidente critico

Este handoff anterior queda parcialmente superado por un incidente nuevo y prioritario.

El 2026-04-01 aparecio un mensaje saliente de control/pairing de OpenClaw dentro de un chat personal real de WhatsApp. Eso invalida cualquier lectura previa de "WhatsApp sano/operativo" como estado util para continuar el proyecto.

La regla vigente pasa a ser:

- WhatsApp queda congelado
- no se reactiva sin verify fail-closed
- no se siguen otros frentes hasta cerrar este incidente

Artefactos nuevos de referencia:

- `docs/WHATSAPP_SAFETY_CONTRACT.md`
- `./scripts/apply_whatsapp_fail_closed.sh`
- `./scripts/verify_whatsapp_fail_closed.sh`

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
- `./scripts/browser_sidecar_extract.sh`
- `./scripts/browser_sidecar_compare.sh`
- `./scripts/browser_sidecar_snapshot.sh`
- `./scripts/browser_sidecar_find.sh`
- `./scripts/verify_browser_sidecar_operational.sh`
- `./scripts/verify_browser_sidecar_real_web.sh`
- `./scripts/verify_browser_sidecar_comparison_lane.sh`
- `./scripts/browser_sidecar_dossier_run.sh`
- `./scripts/verify_browser_sidecar_dossier_lane.sh`
- `./scripts/browser_sidecar_decision_run.sh`
- `./scripts/verify_browser_sidecar_decision_lane.sh`
- `./scripts/browser_sidecar_recommendation_run.sh`
- `./scripts/verify_browser_sidecar_recommendation_lane.sh`
- `./scripts/browser_sidecar_prioritization_run.sh`
- `./scripts/verify_browser_sidecar_prioritization_lane.sh`
- `./scripts/browser_sidecar_execution_tranche_run.sh`
- `./scripts/verify_browser_sidecar_execution_tranche_lane.sh`

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
- el carril ya no solo navega:
  - `browser_sidecar_extract.sh` produce salida estructurada en `json` o `markdown`
  - `browser_sidecar_compare.sh` compara dos paginas reales y puede guardar artefactos
  - los artefactos finales viven en `outbox/manual/`
- `verify_browser_sidecar_comparison_lane.sh` deja `PASS` sobre extract + find + compare + artefactos
- el carril ya no solo compara pares sueltos:
  - `browser_tasks/*.json` deja tareas declarativas versionadas
  - `browser_sidecar_dossier_run.sh` ejecuta una tarea multi-fuente con foco explicito
  - el pipeline guarda extracts, compares y dossier final bajo `outbox/manual/`
  - `verify_browser_sidecar_dossier_lane.sh` deja `PASS` sobre una tarea completa
- el carril ya no solo arma dossiers:
  - `browser_tasks/decision-*.json` deja preguntas concretas con criterios declarativos
  - `browser_sidecar_decision_run.sh` produce matrix + source ranking + veredicto final
  - `verify_browser_sidecar_decision_lane.sh` deja `PASS` sobre una decision publica completa
- el carril ya no solo decide que fuente gana:
  - `browser_tasks/recommend-*.json` deja alternativas explicitas, riesgos, precondiciones y siguiente paso
  - `browser_sidecar_recommendation_run.sh` produce recommendation matrix + runner-up + recomendacion final accionable
  - `verify_browser_sidecar_recommendation_lane.sh` deja `PASS` sobre una recomendacion publica completa
- el carril ya no solo recomienda alternativas publicas:
  - `browser_tasks/prioritize-*.json` deja frentes explicitos del proyecto, buckets y fuentes locales versionadas
  - `browser_sidecar_prioritization_run.sh` produce priority matrix + buckets NOW/NEXT/LATER/FROZEN/DO_NOT_TOUCH/REOPEN_ONLY_IF + siguiente tramo sugerido
  - `verify_browser_sidecar_prioritization_lane.sh` deja `PASS` sobre una priorizacion de proyecto completa
- el carril ya no solo prioriza frentes:
  - `browser_tasks/tranche-*.json` deja candidate tranches explicitos con scope, verify, kill criteria y ticket seed
  - `browser_sidecar_execution_tranche_run.sh` produce tranche selection matrix + ganador + runner-up + execution brief final
  - `verify_browser_sidecar_execution_tranche_lane.sh` deja `PASS` sobre una seleccion completa de tramo ejecutable
- ya hay dos tasks reales resueltas por este carril:
  - `browser_tasks/tranche-golem-openclaw-next-execution.json`
    - ganador: `gateway_channels_public_baseline_pack`
    - runner-up: `truth_surface_reentry_refresh`
  - `browser_tasks/tranche-project-evidence-maintenance-next-execution.json`
    - ganador: `truth_surface_refresh_pack`
    - runner-up: `artifact_index_and_retome_pack`
- hoy ya hay dos tareas ejemplo reales y distintas:
  - `browser_tasks/reserved-domains-technical.json`
  - `browser_tasks/iana-service-overview.json`
  - `browser_tasks/decision-reserved-domains-best-source.json`
  - `browser_tasks/decision-iana-first-source.json`
  - `browser_tasks/recommend-openclaw-public-baseline.json`
  - `browser_tasks/recommend-reserved-domains-reference-pack.json`
  - `browser_tasks/prioritize-golem-openclaw-next-tranche.json`
  - `browser_tasks/prioritize-project-evidence-maintenance.json`
  - `browser_tasks/tranche-golem-openclaw-next-execution.json`
  - `browser_tasks/tranche-project-evidence-maintenance-next-execution.json`
- eleccion deliberada para este tramo:
  - se priorizaron paginas publicas estaticas y estables
  - no se congelo como ejemplo canonico una superficie mas fragil o muy JS-heavy

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
- `docs/BROWSER_DOSSIER_LANE.md`
- `docs/BROWSER_DECISION_LANE.md`
- `docs/BROWSER_RECOMMENDATION_LANE.md`
- `docs/BROWSER_PROJECT_PRIORITIZATION_LANE.md`
- `docs/BROWSER_EXECUTION_TRANCHE_LANE.md`

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
./scripts/verify_browser_sidecar_comparison_lane.sh
./scripts/browser_sidecar_dossier_run.sh browser_tasks/reserved-domains-technical.json
./scripts/verify_browser_sidecar_dossier_lane.sh
./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-reserved-domains-best-source.json
./scripts/verify_browser_sidecar_decision_lane.sh
./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-openclaw-public-baseline.json
./scripts/verify_browser_sidecar_recommendation_lane.sh
./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-golem-openclaw-next-tranche.json
./scripts/verify_browser_sidecar_prioritization_lane.sh
./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-golem-openclaw-next-execution.json
./scripts/verify_browser_sidecar_execution_tranche_lane.sh
./scripts/verify_browser_stack.sh --diagnosis-only
./scripts/verify_worker_orchestration_stack.sh
```

## Que no conviene tocar primero

- No abrir plugins nuevos.
- No convertir esta pausa en expansion de features.
- No vender escritorio completo.
- No escalar workers antes de cerrar browser truth.

## Proximo tramo unico sugerido

El tranche ya seleccionado `gateway_channels_public_baseline_pack` queda ejecutado en forma documental y versionada.

Documento canonico nuevo para reentrada rapida:

- `docs/OPENCLAW_CLI_CHANNELS_BASELINE.md`
- `docs/OPENCLAW_CLI_CHANNELS_MAPPING.md`
- `docs/OPENCLAW_STATUS_EVIDENCE_PACK.md`
- `docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md`
- `docs/OPENCLAW_STATUS_TRIANGULATION_SNAPSHOT_WORKFLOW.md`
- `docs/OPENCLAW_STATUS_SNAPSHOT_TICKET_SEEDS.md`
- `docs/OPENCLAW_STATUS_SEED_INSTANTIATION_EXAMPLES.md`
- `docs/OPENCLAW_STATUS_TICKET_SKELETONS.md`
- `docs/OPENCLAW_STATUS_SKELETON_COMPLETION_EXAMPLES.md`
- `docs/OPENCLAW_STATUS_TICKET_NEAR_FINAL_EXAMPLES.md`
- `docs/OPENCLAW_STATUS_TICKET_FINALIZATION_CHECKLIST.md`
- `docs/OPENCLAW_STATUS_TICKET_CLOSURE_NOTES.md`
- `docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_EXAMPLE.md`
- `docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_STATE_CHECK.md`
- `docs/OPENCLAW_STATUS_STATE_CHECK_CLOSURE_BLOCKED.md`
- `outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md`

Uso correcto de ese baseline:

- planear futuros tickets sobre CLI + channels sin tocar runtime vivo
- usar el mapping pack para decidir que familia entra, con que evidencia y con que verify
- usar el status pack cuando el tramo dependa de snapshots, salud, consistencia o retome
- usar el status consistency pack cuando el tramo compare `gateway status`, `openclaw status` y `channels status --probe`
- usar el status triangulation artifact pack cuando haga falta un snapshot corto, versionable y reusable para ticket o retome
- usar el status triangulation snapshot workflow cuando haga falta saber exactamente como producir ese snapshot y que inputs/outputs exigir segun el caso
- usar el status snapshot ticket seeds pack cuando haga falta pasar de snapshot a ticket read-side concreto sin reinventar objetivo, artifact, verify, kill criteria ni fuera de alcance
- usar el status seed instantiation examples pack cuando haga falta ver como se rellena una seed con una pregunta real y con una artifact concreta antes de escribir el ticket final
- usar el status ticket skeletons pack cuando haga falta pasar de una instancia a un ticket read-side casi completo, todavia no ejecutable, pero ya listo para completarse con artifact real y verify concreta del momento
- usar el status skeleton completion examples pack cuando haga falta ver como se ve uno de esos skeletons ya parcialmente completado, con placeholders honestos para artifact, verify, summaries y conclusion breve
- usar el status ticket near-final examples pack cuando haga falta ver como se ve uno de esos tickets cuando ya esta casi final, con secciones casi definitivas y solo placeholders minimos remanentes
- usar el status ticket finalization checklist pack cuando haga falta decidir si ese near-final example ya puede considerarse ticket real del momento, todavia read-side y sin mutacion
- usar el status ticket closure note pack cuando haga falta dejar la nota final de cierre documental de ese ticket ya completado, con artifact, verify, conclusion permitida y limites todavia vigentes
- usar el real closure note example cuando haga falta ver un caso ya materializado de ese cierre, con una artifact versionada concreta y limites todavia explicitados
- usar `docs/OPENCLAW_STATUS_REAL_CLOSURE_NOTE_STATE_CHECK.md` cuando haga falta ver el segundo cierre real ya materializado, apoyado en `outbox/manual/20260402T005229Z_status-triangulation-artifact_state-check.md`
- leer el state-check closure gate para conservar trazabilidad del bloqueo historico y del destrabe por artifact
- mantener browser nativo fuera
- WhatsApp sigue congelado
- mantener WhatsApp congelado y fuera de alcance
- exigir `./scripts/verify_openclaw_cli_channels_baseline.sh` antes de apoyar un nuevo tramo en esta baseline
- exigir `./scripts/verify_openclaw_cli_channels_mapping.sh` antes de apoyar un nuevo tramo en este mapping
- exigir `./scripts/verify_openclaw_status_evidence_pack.sh` antes de apoyar un nuevo tramo en este status pack
- exigir `./scripts/verify_openclaw_status_consistency_pack.sh` antes de apoyar un nuevo tramo en esta triangulacion
- exigir `./scripts/verify_openclaw_status_triangulation_artifact_pack.sh` antes de apoyar un nuevo tramo en este artifact pack
- exigir `./scripts/verify_openclaw_status_triangulation_snapshot_workflow.sh` antes de apoyar un nuevo tramo en este workflow
- exigir `./scripts/verify_openclaw_status_snapshot_ticket_seeds.sh` antes de apoyar un nuevo tramo en este seeds pack
- exigir `./scripts/verify_openclaw_status_seed_instantiation_examples.sh` antes de apoyar un nuevo tramo en este instantiation pack
- exigir `./scripts/verify_openclaw_status_ticket_skeletons.sh` antes de apoyar un nuevo tramo en este skeletons pack
- exigir `./scripts/verify_openclaw_status_skeleton_completion_examples.sh` antes de apoyar un nuevo tramo en este completion examples pack
- exigir `./scripts/verify_openclaw_status_ticket_near_final_examples.sh` antes de apoyar un nuevo tramo en este near-final examples pack
- exigir `./scripts/verify_openclaw_status_ticket_finalization_checklist.sh` antes de apoyar un nuevo tramo en este finalization checklist pack
- exigir `./scripts/verify_openclaw_status_ticket_closure_notes.sh` antes de apoyar un nuevo tramo en este closure note pack
- exigir `./scripts/verify_openclaw_status_real_closure_note_example.sh` antes de apoyar un nuevo tramo en este ejemplo real
- exigir `./scripts/verify_openclaw_status_state_check_closure_gate.sh` antes de volver a evaluar el segundo cierre real `state-check`

No corresponde volver a discutir antes de eso:

- worker externo real
- delivery mas ambicioso
- control host mas fuerte
- nuevas superficies funcionales
