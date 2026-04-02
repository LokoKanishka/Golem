# Browser Execution Tranche Lane

## Que agrega sobre el project prioritization lane

El execution tranche lane no reemplaza al project prioritization lane.

Lo usa como upstream y agrega:

- candidatos de tramo reales, no solo frentes
- un ganador unico
- runner-up explicito
- alcance y no alcance
- acceptance criteria
- verify obligatoria
- kill criteria
- artefactos esperados
- y un execution brief listo para ticket

El prioritization lane responde "que frente del proyecto conviene mover ahora".
El execution tranche lane responde "que tramo concreto, acotado y defendible conviene ejecutar dentro de esos frentes".

## Decision de diseno

Esta capa es una extension natural del priorization lane, pero vive como familia separada de manifests.

No conviene meter `candidate_tranches` dentro de `project_fronts` porque:

- un `front` sigue siendo una unidad estrategica corta
- un `candidate_tranche` es una unidad operativa ejecutable
- mezclar ambos degradaria la claridad del runner actual

La arquitectura queda asi:

- `browser_tasks/prioritize-*.json` sigue definiendo frentes y buckets
- `browser_tasks/tranche-*.json` define candidates concretos de ejecucion
- `browser_sidecar_execution_tranche_run.sh` consume evidencia publica, estado local versionado y un `prioritization_task` upstream
- el resultado final es un brief ejecutable con ganador y runner-up

## Formato canonico

Una task de execution tranche define:

- `task_id`
- `title`
- `description`
- `question`
- `prioritization_task`
- `sources`
- `local_sources`
- `focus_terms`
- `expected_signals`
- `decision_criteria`
- `candidate_tranches`
- `output_slug`

Cada `candidate_tranche` define como minimo:

- `tranche_id`
- `label`
- `description`
- `goal`
- `supporting_fronts`
- `evidence_sources`
- `relative_effort`
- `in_scope`
- `out_of_scope`
- `acceptance_criteria`
- `preconditions`
- `risk_hints`
- `kill_criteria`
- `required_artifacts`
- `verify_requirements`
- `implementation_ticket_seed`
- `notes`

## Regla de seleccion

La regla actual es explicita y chica:

- primero se hereda fuerza desde los buckets del `prioritization_task`
- despues se evalua cada tranche con criterios declarativos y evidencia visible
- luego se penaliza por esfuerzo relativo y blockers
- el ranking final ordena por:
  - `execution_score`
  - `priority_strength_score`
  - menor esfuerzo relativo
  - `tranche_id`

No hay IA opaca ni scoring escondido.

## Formato del brief final

El brief final deja, como minimo:

- pregunta
- upstream prioritization usado
- tranche selection matrix
- tranche ganadora
- runner-up
- in_scope
- out_of_scope
- acceptance criteria
- required artifacts
- verify requirements
- risks
- preconditions
- kill criteria
- why-now
- why-not-others
- frozen context heredado
- implementation ticket seed

Salida final:

- markdown legible
- json estructurado

## Tasks reales versionadas

- `browser_tasks/tranche-golem-openclaw-next-execution.json`
- `browser_tasks/tranche-project-evidence-maintenance-next-execution.json`

## Comando principal

```bash
./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-golem-openclaw-next-execution.json
```

Ejemplos:

```bash
./scripts/browser_sidecar_execution_tranche_run.sh browser_tasks/tranche-project-evidence-maintenance-next-execution.json
./scripts/browser_sidecar_execution_tranche_run.sh --format json browser_tasks/tranche-golem-openclaw-next-execution.json
```

## Artefactos

El lane sigue usando `outbox/manual/`.

Por corrida deja:

- artefactos publicos de extract
- artefactos locales versionados
- artefactos del `prioritization_task` upstream
- matriz final de tranche en `json`
- execution brief final en `md`

Convencion:

- timestamp UTC
- `output_slug`
- tipo de artefacto

## Verify

```bash
./scripts/verify_browser_sidecar_execution_tranche_lane.sh
```

La pregunta que debe poder responder esta verify es:

`¿el Browser Sidecar Execution Tranche Lane sigue vivo y puede elegir un unico tramo con evidencia, runner-up y brief final?`

La respuesta esperada es:

`SI`

## Limites honestos

- no toca `openclaw browser ...`
- no toca runtime vivo
- no reabre WhatsApp
- no deshace el fail-closed
- no abre workers reales
- no usa login
- no vende control host total
- no reemplaza juicio humano; lo estructura y lo deja auditable
