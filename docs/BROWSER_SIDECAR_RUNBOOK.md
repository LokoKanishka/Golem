# Browser Sidecar Runbook

## Que es

El browser sidecar es el carril browser operativo oficial de Golem.

No usa `openclaw browser ...` como superficie diaria.
Usa un Chrome dedicado con CDP y los wrappers `browser_sidecar_*`.

## Por que se acepta

Se acepta porque hoy es el unico carril browser que ya quedo en `PASS` para:

- listar tabs reales
- leer una pagina real
- buscar texto real
- navegar y leer paginas publicas reales simples

La deuda congelada queda en el browser nativo de OpenClaw.

## Decision de diseño

La interfaz actual queda separada asi:

- `snapshot`: volcado crudo del contenido visible y links de una tab
- `read`: lectura rapida para humano, encima de `snapshot`
- `extract`: salida estructurada y normalizada para trabajo real
- `compare`: comparacion operativa entre dos paginas usando la salida de `extract`
- `dossier`: pipeline declarativo multi-fuente para una tarea publica reproducible
- `decision`: capa de pregunta + criterios + matriz + veredicto encima del dossier
- `recommendation`: capa de alternativas + riesgos + precondiciones + siguiente paso encima de la decision
- `prioritization`: capa de frentes del proyecto + buckets + kill criteria + siguiente tramo encima de la recommendation
- `execution tranche`: capa de candidate tranches + winner + runner-up + brief ejecutable encima de la prioritization

La regla es simple:

- si queremos inspeccion manual rapida: `read`
- si queremos estructura reusable o artefactos: `extract`
- si queremos diferencias entre dos paginas: `compare`

## Configuracion por defecto

- puerto CDP: `9222`
- URL CDP: `http://127.0.0.1:9222`
- root runtime: `/tmp/golem-browser-sidecar`
- profile runtime: `/tmp/golem-browser-sidecar/profile`
- log runtime: `/tmp/golem-browser-sidecar/chrome.log`

Overrides soportados:

- `GOLEM_BROWSER_SIDECAR_ROOT`
- `GOLEM_BROWSER_SIDECAR_PORT`
- `GOLEM_BROWSER_SIDECAR_URL`
- `GOLEM_BROWSER_SIDECAR_PROFILE_DIR`
- `GOLEM_BROWSER_SIDECAR_PIDFILE`
- `GOLEM_BROWSER_SIDECAR_LOGFILE`
- `GOLEM_BROWSER_SIDECAR_BROWSER_BIN`

## Lifecycle

Arrancar:

```bash
./scripts/browser_sidecar_start.sh
```

Ver estado:

```bash
./scripts/browser_sidecar_status.sh
```

Apagar:

```bash
./scripts/browser_sidecar_stop.sh
```

## Comandos diarios

Abrir URL:

```bash
./scripts/browser_sidecar_open.sh http://127.0.0.1:8011/
```

Listar tabs:

```bash
./scripts/browser_sidecar_tabs.sh
```

Seleccionar una tab por indice, titulo parcial o URL parcial:

```bash
./scripts/browser_sidecar_select.sh 0
./scripts/browser_sidecar_select.sh "Reserved Domains"
./scripts/browser_sidecar_select.sh rfc-editor.org
```

Si el selector es ambiguo, el script falla y muestra los matches.

Leer una tab de forma directa:

```bash
./scripts/browser_sidecar_read.sh
./scripts/browser_sidecar_read.sh "Reserved Domains"
./scripts/browser_sidecar_read.sh rfc-editor.org
./scripts/browser_sidecar_read.sh https://www.iana.org/domains/reserved
```

Snapshot de la tab actual o por selector:

```bash
./scripts/browser_sidecar_snapshot.sh
./scripts/browser_sidecar_snapshot.sh "Golem Browser Truth"
./scripts/browser_sidecar_snapshot.sh http://127.0.0.1:8011/
```

Buscar texto:

```bash
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415 "Golem Browser Truth"
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415 http://127.0.0.1:8011/
```

Extraccion estructurada:

```bash
./scripts/browser_sidecar_extract.sh "Reserved Domains"
./scripts/browser_sidecar_extract.sh --format json rfc-editor.org
./scripts/browser_sidecar_extract.sh --save-slug browser-sidecar-iana "Reserved Domains"
```

Comparacion entre dos paginas:

```bash
./scripts/browser_sidecar_compare.sh "Reserved Domains" rfc-editor.org
./scripts/browser_sidecar_compare.sh --format json "Reserved Domains" rfc-editor.org
./scripts/browser_sidecar_compare.sh --save-slug browser-sidecar-compare "Reserved Domains" rfc-editor.org
```

Pipeline de dossier:

```bash
./scripts/browser_sidecar_dossier_run.sh browser_tasks/reserved-domains-technical.json
./scripts/browser_sidecar_dossier_run.sh browser_tasks/iana-service-overview.json
./scripts/browser_sidecar_dossier_run.sh --format json browser_tasks/reserved-domains-technical.json
```

Pipeline de decision:

```bash
./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-reserved-domains-best-source.json
./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-iana-first-source.json
./scripts/browser_sidecar_decision_run.sh --format json browser_tasks/decision-reserved-domains-best-source.json
```

Pipeline de recommendation:

```bash
./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-openclaw-public-baseline.json
./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-reserved-domains-reference-pack.json
./scripts/browser_sidecar_recommendation_run.sh --format json browser_tasks/recommend-openclaw-public-baseline.json
```

Pipeline de project prioritization:

```bash
./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-golem-openclaw-next-tranche.json
./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-project-evidence-maintenance.json
./scripts/browser_sidecar_prioritization_run.sh --format json browser_tasks/prioritize-golem-openclaw-next-tranche.json
```

Pipeline de execution tranche:

```bash
./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-golem-openclaw-next-execution.json
./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-project-evidence-maintenance-next-execution.json
./scripts/browser_sidecar_execution_tranche_run.sh --format json browser_tasks/tranche-golem-openclaw-next-execution.json
```

Artefactos:

- los artefactos finales viven en `outbox/manual/`
- `extract --save-slug ...` guarda `json` y `md`
- `compare --save-slug ...` guarda `json` y `md`
- `dossier_run` guarda extracts, compares y un dossier final en `json` y `md`
- `decision_run` guarda el dossier base y un artefacto final de decision en `json` y `md`
- `recommendation_run` guarda dossier base, decision base y un artefacto final de recommendation en `json` y `md`
- `prioritization_run` guarda extracts publicos, extracts locales versionados y un artefacto final de priorizacion en `json` y `md`
- `execution_tranche_run` guarda extracts publicos/locales, reutiliza el artefacto de priorizacion upstream y deja una matriz final + execution brief en `json` y `md`
- si una fuente publica JS-heavy no deja texto visible util, `prioritization_run` conserva la prueba sidecar y agrega un fallback HTML versionado
- no hace falta tocar `.gitignore` porque `outbox/manual/` ya esta ignorado

## Verify

Verify truth mas profunda:

```bash
./scripts/verify_browser_capability_truth.sh
```

Verify operativa corta:

```bash
./scripts/verify_browser_sidecar_operational.sh
```

Verify real sobre web publica simple:

```bash
./scripts/verify_browser_sidecar_real_web.sh
```

Verify larga de lectura/comparacion:

```bash
./scripts/verify_browser_sidecar_comparison_lane.sh
```

Verify larga de dossier:

```bash
./scripts/verify_browser_sidecar_dossier_lane.sh
```

Verify larga de decision:

```bash
./scripts/verify_browser_sidecar_decision_lane.sh
```

Verify larga de recommendation:

```bash
./scripts/verify_browser_sidecar_recommendation_lane.sh
```

Verify larga de project prioritization:

```bash
./scripts/verify_browser_sidecar_prioritization_lane.sh
```

Verify larga de execution tranche:

```bash
./scripts/verify_browser_sidecar_execution_tranche_lane.sh
```

Targets hoy probados de forma explicita:

- `https://www.iana.org/domains/reserved`
- `https://www.rfc-editor.org/rfc/rfc2606.html`
- `https://www.rfc-editor.org/rfc/rfc6761.html`
- `https://www.iana.org/about`
- `https://www.iana.org/performance`
- `https://www.iana.org/about/excellence`

Tareas declarativas ejemplo hoy versionadas:

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

## Que NO promete

- no arregla `openclaw browser ...`
- no usa el Chrome ambient como contrato confiable
- no promete login, clicks complejos o formularios
- no promete scraping general de sitios frágiles o anti-bot
- no promete comparacion semantica profunda ni NLP
- no promete investigacion publica general sin foco declarativo
- no promete decision automatica sin criterios explicitos
- no promete recomendacion practica sin alternativas ni evidencia trazable
- no promete priorizacion de proyecto sin frentes, buckets ni evidencia local versionada
- no promete un execution brief sin un `prioritization_task` upstream ni candidate tranches explicitos
- no promete control host total
- no reabre MCP, plugins ni workers
- no convierte al browser nativo de OC en sano

## Deuda congelada

La deuda congelada es explicita:

- `browser nativo OC = BLOCKED`
- el carril operativo de browser real va por sidecar
