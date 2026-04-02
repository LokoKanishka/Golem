# Browser Project Prioritization Lane

## Que agrega sobre el recommendation lane

El project prioritization lane no reemplaza al recommendation lane.

Lo usa como base conceptual y agrega:

- frentes explicitos del proyecto
- evidencia publica y evidencia local versionada en la misma corrida
- buckets operativos explicitos
- kill criteria
- `DO_NOT_TOUCH`
- `REOPEN_ONLY_IF`
- siguiente tramo recomendado para el proyecto

El recommendation lane responde "que alternativa conviene".
El prioritization lane responde "que frente mover ahora, cual congelar y bajo que condicion reabrirlo".
El execution tranche lane responde "que tramo concreto ejecutar ahora dentro de esos frentes".

## Decision de diseno

La arquitectura se mantiene contenida:

- `browser_tasks/*.json` sigue siendo el directorio canonico
- `browser_sidecar_prioritization_run.sh` no reemplaza extract/decision/recommendation
- reutiliza el sidecar para evidencia publica
- lee tambien docs versionadas del repo como evidencia local

No abre otro framework.
Agrega una capa de priorizacion dura encima de verdades ya aceptadas.

La continuacion natural ahora es:

- `execution tranche lane`

## Formato canonico

Una task de priorizacion agrega sobre las tasks previas:

- `local_sources`
- `project_fronts`
- `priority_buckets`

Cada `project_front` define como minimo:

- `front_id`
- `label`
- `description`
- `current_state_hint`
- `evidence_sources`
- `intended_outcome`
- `relative_cost`
- `relative_cost_note`
- `risk_hints`
- `preconditions`
- `kill_criteria`
- `blocking_signals`
- `bucket_signal_terms`
- `recommended_action`

Buckets canonicos usados hoy:

- `NOW`
- `NEXT`
- `LATER`
- `FROZEN`
- `DO_NOT_TOUCH`
- `REOPEN_ONLY_IF`

## Regla de bucket

La asignacion actual es explicita:

- primero se buscan senales forzadas para `FROZEN`, `DO_NOT_TOUCH` o `REOPEN_ONLY_IF`
- si no aparecen, se calcula `priority_score` con:
  - evidencia positiva por criterio
  - penalizacion por blockers
  - penalizacion por costo relativo
- luego el frente cae en `NOW`, `NEXT` o `LATER`

No hay scoring oculto ni judgement opaco.

## Tasks reales versionadas

- `browser_tasks/prioritize-golem-openclaw-next-tranche.json`
- `browser_tasks/prioritize-project-evidence-maintenance.json`

## Comando principal

```bash
./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-golem-openclaw-next-tranche.json
```

Ejemplos:

```bash
./scripts/browser_sidecar_prioritization_run.sh browser_tasks/prioritize-project-evidence-maintenance.json
./scripts/browser_sidecar_prioritization_run.sh --format json browser_tasks/prioritize-golem-openclaw-next-tranche.json
```

## Artefactos

El prioritization lane sigue usando `outbox/manual/`.

Por corrida deja:

- extracts publicos
- extracts locales versionados
- matriz final de priorizacion en `json`
- reporte final de priorizacion en `md`

Nota operativa:

- el lane intenta primero leer fuentes publicas via sidecar visible
- si una fuente publica abre pero no expone texto visible util en una doc JS-heavy, conserva igual el artefacto sidecar y agrega un fallback HTML versionado para no perder evidencia publica trazable

El artefacto final incluye:

- pregunta
- fuentes publicas
- fuentes locales versionadas
- priority matrix por frente
- bucket overview
- frente recomendado
- runner-up
- siguiente tramo sugerido
- incertidumbres

La capa siguiente toma ese output y lo convierte en:

- un unico `candidate_tranche` ganador
- un runner-up
- alcance / no alcance
- acceptance criteria
- verify obligatoria
- kill criteria
- execution brief final

## Verify

```bash
./scripts/verify_browser_sidecar_prioritization_lane.sh
```

Luego:

```bash
./scripts/verify_browser_sidecar_execution_tranche_lane.sh
```

## Limites honestos

- no toca `openclaw browser ...`
- no toca runtime vivo
- no usa login
- no abre workers reales
- no vende control host total
- no reabre browser nativo por opinion
- no reemplaza juicio humano; lo estructura y lo hace auditable
