# Chain Plan Contract

## Estado

Este contrato formaliza el `chain_plan` que hoy ya usa Golem para orquestacion v2/v3.

No define un scheduler gigante.
Define el contrato minimo para que planes con workers, barriers y continuaciones entren bien formados antes de ejecutarse.

## Objetivo

Un `chain_plan` debe permitir:

- describir steps locales y worker de forma estable
- declarar dependencias explicitas entre steps
- declarar join barriers / await groups cuando hagan falta
- validar que el plan no contiene contradicciones basicas
- proteger a los runners contra planes ambiguos o incoherentes

## Forma canonica

Un `chain_plan` puede vivir:

- embebido en una root task bajo `chain_plan`
- como documento JSON standalone

La forma canonica nueva usa:

- `plan_kind`
- `plan_version`
- `steps`
- `dependency_groups`

Compatibilidad:

- el repo actual todavia acepta `version` como alias legado de `plan_version`
- `step_name` sigue siendo el identificador estable del step
- `execution_mode` sigue siendo el campo canonico para distinguir `local` vs `worker`

## Top-level fields

Campos minimos:

- `plan_kind`: hoy el valor esperado es `chain_plan`
- `plan_version`: version del contrato del plan, por ejemplo `2.4` o `3.0`
- `steps`: lista ordenable de steps

Campos opcionales pero recomendados:

- `dependency_groups`
- `step_count`
- `local_step_count`
- `worker_step_count`
- `critical_step_count`
- `await_worker_result_step_count`
- `conditional_step_count`
- `dependency_group_count`
- `mixes_execution_modes`
- `manual_worker_controlled`
- `supports_conditional_steps`

## Step contract

Cada step debe declarar como minimo:

- `step_name`: identificador estable y unico dentro del plan
- `step_order`: entero positivo unico
- `task_type`
- `execution_mode`: `local` o `worker`
- `critical`: booleano
- `title`
- `objective`
- `depends_on_step_names`: lista de `step_name`

Campos opcionales:

- `status`
- `child_task_id`
- `await_worker_result`
- `await_group`
- `join_group`
- `condition_source_step`
- `run_if_worker_result_status`
- `output_mode`

Semantica minima:

- `step_name` es la identidad estable del step
- `depends_on_step_names` declara las dependencias directas
- `await_worker_result` solo tiene sentido para steps `worker`
- `await_group` agrupa workers awaited que forman parte de la misma espera/barrier
- `join_group` declara que un step local depende de un barrier explicitado en `dependency_groups`
- `condition_source_step` y `run_if_worker_result_status` modelan continuacion condicional en v3

## Dependency groups

`dependency_groups` es una lista opcional.

Cada grupo debe declarar:

- `group_name`
- `group_type`: `await_group` o `join_barrier`
- `step_names`
- `satisfaction_policy`

Campos opcionales:

- `used_by_step_names`
- `continue_on_blocked`
- `continue_on_failed`

Semantica minima actual:

- `satisfaction_policy` soportado: `all_done`
- un `await_group` agrupa worker steps con `await_worker_result: true`
- un `join_barrier` representa el barrier que habilita uno o mas steps locales posteriores
- `used_by_step_names` debe apuntar a los steps locales que consumen ese barrier
- `continue_on_blocked` y `continue_on_failed` hoy existen como politica minima, aunque los planes builtin actuales usan `false`

## Reglas de validacion

La validacion previa debe rechazar como minimo:

- `step_name` duplicados
- `step_order` duplicados
- dependencias hacia steps inexistentes
- ciclos de dependencias
- dependencias hacia steps posteriores o del mismo orden
- `dependency_groups` vacios o mal formados
- referencias a groups inexistentes
- `await_worker_result` sobre steps `local`
- `await_group` sobre steps que no son worker awaited
- `join_group` sobre steps que no son locales
- condicion condicional incompleta o referenciando un step fuente inexistente
- barriers cuyo `used_by_step_names` no coincide con los steps que dicen consumirlos
- steps locales cuyo `join_group` contradice sus dependencias declaradas

## Compatibilidad actual

El validador del repo acepta planes legados cuando:

- usan `version` en lugar de `plan_version`
- no declaran `dependency_groups` porque todavia no usan barriers explicitos
- usan solo `depends_on_step_names` para la politica de continuacion

Los planes builtin nuevos del repo deben escribir:

- `plan_kind: chain_plan`
- `plan_version`

## Entry point oficial

La validacion reproducible vive en:

```text
./scripts/validate_chain_plan.sh <task_id|task_json_path|plan_json_path>
```

Ese comando debe usarse antes de ejecutar chains complejas y tambien sirve como evidencia reproducible del contrato.
