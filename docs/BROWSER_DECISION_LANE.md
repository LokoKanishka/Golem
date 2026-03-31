# Browser Decision Lane

## Que agrega sobre el dossier lane

El decision lane no reemplaza al dossier lane.

Lo usa como base y agrega:

- una pregunta publica concreta
- criterios explicitos
- pesos simples
- evidencia rastreable por criterio
- matriz de decision
- veredicto final con incertidumbres

Esta capa ahora tambien tiene una continuacion explicita:

- `recommendation lane`

El decision lane responde que fuente o superficie gana segun criterios.
El recommendation lane traduce esa matriz a alternativas de proyecto, riesgos, precondiciones y siguiente paso.

## Decision de diseño

La arquitectura se mantiene chica:

- `browser_sidecar_dossier_run.sh` sigue siendo la capa de recoleccion multi-fuente
- `browser_sidecar_decision_run.sh` consume el dossier JSON y produce decision
- `browser_sidecar_recommendation_run.sh` consume la decision y rankea alternativas
- `browser_tasks/*.json` sigue siendo el directorio canonico

No se abrio otra familia de manifests fuera de `browser_tasks/`.
La separacion se hace por campos:

- una task de decision agrega `question`
- y agrega `decision_criteria`

## Formato canónico

Campos nuevos:

- `question`
- `decision_criteria`

Cada criterio define:

- `criterion_id`
- `label`
- `description`
- `weight`
- `evidence_terms`
- `scoring_rule`
- `notes`

La regla actual de scoring es simple y explicita:

- `0`: sin evidencia
- `2`: cobertura minima
- `3`: cobertura moderada
- `4`: cobertura fuerte con soporte adicional
- `5`: cobertura muy fuerte

Luego:

- `weighted_score = score * weight`

## Tareas reales versionadas

- `browser_tasks/decision-reserved-domains-best-source.json`
- `browser_tasks/decision-iana-first-source.json`
- `browser_tasks/recommend-openclaw-public-baseline.json`
- `browser_tasks/recommend-reserved-domains-reference-pack.json`

## Comando principal

```bash
./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-reserved-domains-best-source.json
```

Ejemplos:

```bash
./scripts/browser_sidecar_decision_run.sh browser_tasks/decision-iana-first-source.json
./scripts/browser_sidecar_decision_run.sh --format json browser_tasks/decision-reserved-domains-best-source.json
```

## Artefactos

El decision lane sigue usando `outbox/manual/`.

Por corrida deja:

- extracts por fuente
- compares por par
- dossier base
- decision final en `json`
- decision final en `md`

El artefacto final de decision incluye:

- pregunta
- source ranking
- criterion matrix
- recommended source
- confidence
- rationale
- uncertainties

## Verify

```bash
./scripts/verify_browser_sidecar_decision_lane.sh
```

La continuacion natural hoy es:

```bash
./scripts/verify_browser_sidecar_recommendation_lane.sh
```

## Limites honestos

- no usa login
- no hace clicks complejos
- no decide con IA opaca
- no reemplaza juicio humano
- no inventa evidencia fuera del texto visible
- no toca el browser nativo de OC
