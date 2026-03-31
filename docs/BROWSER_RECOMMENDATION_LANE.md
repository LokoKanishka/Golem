# Browser Recommendation Lane

## Que agrega sobre el decision lane

El recommendation lane no reemplaza al decision lane.

Lo usa como base y agrega:

- alternativas explicitas
- ranking por alternativa
- costo relativo declarado
- riesgos y precondiciones visibles
- runner-up
- alternativas descartadas con razones
- siguiente tramo sugerido

El dossier organiza.
El decision lane elige evidencia por criterio.
El recommendation lane traduce eso a una propuesta practica de proyecto.

Esta capa ahora tambien tiene una continuacion explicita:

- `project prioritization lane`

## Decision de diseno

La arquitectura sigue contenida:

- `browser_sidecar_dossier_run.sh` sigue reuniendo fuentes y compares
- `browser_sidecar_decision_run.sh` sigue produciendo la matriz por criterio
- `browser_sidecar_recommendation_run.sh` consume esa decision y rankea alternativas
- `browser_sidecar_prioritization_run.sh` consume evidencia publica + local para rankear frentes del proyecto
- `browser_tasks/*.json` sigue siendo el directorio canonico

No se abrio otra familia de manifests fuera de `browser_tasks/`.

## Formato canonico

Una task de recomendacion sigue siendo un superset del manifest de decision:

- `question`
- `decision_criteria`
- `alternatives`

Cada alternativa define:

- `alternative_id`
- `label`
- `description`
- `intended_outcome`
- `source_plan`
- `primary_source`
- `relative_cost`
- `relative_cost_note`
- `risk_hints`
- `preconditions`
- `suggested_next_step`
- `notes`

## Regla de ranking

La regla actual es simple y explicita:

- por criterio, cada alternativa toma el mejor `weighted_score` disponible dentro de su `source_plan`
- `total_evidence_score` = suma de esos mejores `weighted_score`
- el ranking final ordena por:
  - `total_evidence_score`
  - cantidad de criterios ganados
  - costo relativo (`low > medium > high`)
  - menos precondiciones
  - menos riesgos declarados

No hay IA opaca ni scoring oculto.

## Tasks reales versionadas

- `browser_tasks/recommend-openclaw-public-baseline.json`
- `browser_tasks/recommend-reserved-domains-reference-pack.json`
- `browser_tasks/prioritize-golem-openclaw-next-tranche.json`
- `browser_tasks/prioritize-project-evidence-maintenance.json`

## Comando principal

```bash
./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-openclaw-public-baseline.json
```

Ejemplos:

```bash
./scripts/browser_sidecar_recommendation_run.sh browser_tasks/recommend-reserved-domains-reference-pack.json
./scripts/browser_sidecar_recommendation_run.sh --format json browser_tasks/recommend-openclaw-public-baseline.json
```

## Artefactos

El recommendation lane sigue usando `outbox/manual/`.

Por corrida deja:

- extracts por fuente
- compares por par
- dossier base
- decision base
- recommendation final en `json`
- recommendation final en `md`

El artefacto final incluye:

- pregunta
- ranking por alternativa
- recommendation matrix
- recomendacion principal
- runner-up
- riesgos
- precondiciones
- incertidumbres
- siguiente paso sugerido

## Verify

```bash
./scripts/verify_browser_sidecar_recommendation_lane.sh
```

La continuacion natural hoy es:

```bash
./scripts/verify_browser_sidecar_prioritization_lane.sh
```

## Limites honestos

- no toca `openclaw browser ...`
- no usa login
- no hace clicks complejos
- no reemplaza juicio humano
- no inventa evidencia fuera del texto visible
- no convierte fuentes publicas en prueba de host local
- no abre workers, MCP ni control host total
