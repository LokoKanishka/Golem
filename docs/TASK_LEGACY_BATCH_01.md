# Legacy Task Batch 01: First Controlled Migration

## Propósito

Este tramo abre la primera tanda real de migración de tareas legacy activas.

Después de:

- abrir el carril canónico;
- cerrar lifecycle, evidence/artifacts y validate/archive;
- barrer el inventario real;
- aislar los 4 corruptos vacíos;

el estado operativo quedó en condiciones de empezar migración real.

La regla de este tramo es simple:

- no migrar en masa;
- migrar una tanda chica;
- validar todo en estricto;
- dejar evidencia auditable;
- rerun del baseline al final.

---

## Tamaño de tanda

Esta primera tanda toma:

- las primeras 10 tareas `legacy` activas detectadas en `diagnostics/task_audit/active_scan.txt`

La idea no es optimizar volumen.
La idea es verificar que el carril real de migración funciona sobre datos verdaderos del repo.

---

## Salidas esperadas

Se generan estos artefactos:

- `diagnostics/task_audit/legacy_batch_01_candidates.txt`
- `diagnostics/task_audit/legacy_batch_01_dry_run.txt`
- `diagnostics/task_audit/legacy_batch_01_migrated.txt`
- `diagnostics/task_audit/legacy_batch_01_validate.txt`
- `docs/TASK_LEGACY_BATCH_01.md`

---

## Regla de este tramo

Este paso sí hace migración real, pero solo si:

1. el scan de candidatos existe;
2. el dry-run no falla;
3. cada tarea migrada valida en `--strict`.

Si algo falla, el lote debe cortar ahí y no fingir éxito parcial silencioso.

---

## Resultado esperado

Si todo sale bien, después del rerun del baseline debería verse, aproximadamente:

- `legacy` activo: 1395 -> 1385
- `canonical` activo: 0 -> 10
- `corrupt`: sigue en 0
- `invalid`: sigue en 0

---

## Implicación

Con esta primera tanda cerrada, el siguiente paso correcto será decidir si:

- repetimos Batch 02 con otra tanda chica;
- o primero inspeccionamos la calidad real de los migrados antes de escalar.

