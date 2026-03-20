# Legacy Task Batch 02: Controlled Migration

## Propósito

Este tramo abre la segunda tanda real de migración de tareas legacy activas.

Batch 01 ya probó tres cosas importantes sobre datos reales del repo:

- la migración funciona;
- la validación estricta pasa;
- la quality gate semántica mínima salió limpia.

Por eso ahora corresponde escalar un poco, pero manteniendo control.

---

## Tamaño de tanda

Esta segunda tanda toma:

- las primeras 25 tareas `legacy` activas detectadas en `diagnostics/task_audit/active_scan.txt`

No se busca velocidad bruta.
Se busca seguir avanzando con lote razonable y auditable.

---

## Salidas esperadas

Se generan estos artefactos:

- `diagnostics/task_audit/legacy_batch_02_candidates.txt`
- `diagnostics/task_audit/legacy_batch_02_dry_run.txt`
- `diagnostics/task_audit/legacy_batch_02_migrated.txt`
- `diagnostics/task_audit/legacy_batch_02_validate.txt`
- `docs/TASK_LEGACY_BATCH_02.md`

---

## Regla de este tramo

Este paso sí hace migración real, pero solo si:

1. el scan de candidatos existe;
2. el dry-run no falla;
3. cada tarea migrada valida en `--strict`.

Si algo falla, el lote corta ahí.

---

## Resultado esperado

Si todo sale bien, después del rerun del baseline debería verse, aproximadamente:

- `canonical` activo: 10 -> 35
- `legacy` activo: 1385 -> 1360
- `corrupt`: sigue en 0
- `invalid`: sigue en 0

---

## Implicación

Con Batch 02 cerrado, el siguiente paso correcto será decidir si ya conviene:

- repetir Batch 03 con otro lote moderado;
- o introducir primero un runner parametrizable para tandas sucesivas.

