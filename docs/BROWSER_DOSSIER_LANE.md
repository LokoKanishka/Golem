# Browser Dossier Lane

## Que resuelve

El dossier lane eleva el browser sidecar desde `extract + compare` a una tarea reproducible de investigacion publica chica.

No promete agencia total.
Si promete un pipeline verificable para:

- cargar una tarea declarativa
- abrir un conjunto chico de fuentes publicas
- extraer cada fuente con formato estable
- aplicar focos de lectura explicitos
- comparar pares relevantes
- producir un dossier final con artefactos trazables

Esta capa ahora tambien tiene una continuacion explicita:

- `decision lane`
- `recommendation lane`
- `project prioritization lane`
- `execution tranche lane`

El dossier organiza y sintetiza.
El decision lane evalua una pregunta concreta con criterios y veredicto.
El recommendation lane toma esa decision y la convierte en una recomendacion practica con alternativas.
El project prioritization lane usa evidencia publica + local para decidir que frente del proyecto mover ahora y cual congelar.
El execution tranche lane toma esos frentes priorizados y elige un unico tramo ejecutable con alcance, verify y kill criteria.

## Decision de diseno

La capa nueva vive encima del carril sidecar ya aceptado.

No abre otro framework.
Reusa:

- `browser_sidecar_open.sh`
- `browser_sidecar_extract.sh`
- `browser_sidecar_compare.sh`

Y agrega un unico orquestador:

- `browser_sidecar_dossier_run.sh`

La tarea declarativa vive en `browser_tasks/*.json`.

## Formato de tarea

Campos canonicos:

- `task_id`
- `title`
- `description`
- `output_slug`
- `comparison_mode`
- `focus_terms`
- `expected_signals`
- `focus_profile`
- `sources`
- `comparisons`

Cada `source` define:

- `label`
- `url`
- `selector_hint` opcional
- `notes` opcional

Cada `comparison` define:

- `label`
- `left`
- `right`

## Foco de lectura

En este carril, el foco es deliberadamente simple:

- `focus_terms`: frases o terminos que importa localizar
- `expected_signals`: senales que esperamos encontrar si la fuente es relevante
- `focus_profile`: limites chicos de excerpt y muestras

No hay IA en esta capa.
La lectura estructurada sale de texto visible normalizado y matching explicito.

## Comando principal

```bash
./scripts/browser_sidecar_dossier_run.sh browser_tasks/reserved-domains-technical.json
```

Opciones utiles:

```bash
./scripts/browser_sidecar_dossier_run.sh --format json browser_tasks/iana-service-overview.json
./scripts/browser_sidecar_dossier_run.sh --save-slug reserved-dossier browser_tasks/reserved-domains-technical.json
```

## Tareas ejemplo versionadas

- `browser_tasks/reserved-domains-technical.json`
- `browser_tasks/iana-service-overview.json`

Se eligieron porque son publicas, estables y textuales.

Nota operativa:

- se considero usar superficies institucionales mas pesadas como `pti.icann.org/about`
- no quedaron como task ejemplo canonica porque este tramo prioriza reproducibilidad sobre paginas estaticas y no fragiles

## Artefactos

El dossier lane usa `outbox/manual/` como carril canonico.

Por tarea genera:

- extracts por fuente en `json` y `md`
- compares por par en `json` y `md`
- dossier final en `json` y `md`

Convencion:

- timestamp UTC
- `output_slug`
- tipo de artefacto
- label de fuente o comparison cuando aplica

## Verify

Verify larga de dossier:

```bash
./scripts/verify_browser_sidecar_dossier_lane.sh
```

Tambien siguen vigentes:

- `./scripts/verify_browser_sidecar_real_web.sh`
- `./scripts/verify_browser_sidecar_comparison_lane.sh`
- `./scripts/verify_browser_sidecar_decision_lane.sh`
- `./scripts/verify_browser_sidecar_recommendation_lane.sh`

## Limites vigentes

- no usa `openclaw browser ...`
- no hace login
- no hace clicks complejos ni formularios
- no promete scraping general anti-bot
- no reemplaza una capa semantica profunda
- no abre workers, MCP ni control host total

## Estado operativo

El carril browser oficial sigue siendo solo el sidecar.

La deuda congelada sigue siendo:

- `browser nativo OC = BLOCKED`
