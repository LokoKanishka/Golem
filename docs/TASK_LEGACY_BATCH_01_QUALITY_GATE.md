# Legacy Batch 01: Quality Gate

## Propósito

Este tramo no migra tareas nuevas.

Su objetivo es inspeccionar la calidad real de las 10 tareas ya migradas en Batch 01,
para confirmar que el carril no solo produce JSON estrictamente válidos, sino también
migraciones semánticamente razonables.

---

## Regla de este tramo

No se toca ninguna tarea.
No se reescribe nada.
No se abre Batch 02 todavía.

Solo se hace:

1. releer las 10 migradas;
2. validar en estricto;
3. comprobar señales mínimas de buena migración;
4. generar un reporte auditable;
5. corregir el texto genérico del baseline para que ya no hable de `corrupt` como próximo paso.

---

## Qué se chequea

Para cada tarea migrada se verifica, como mínimo:

- el archivo existe;
- valida en `--strict`;
- el `id` coincide con el nombre de archivo;
- existe acción `migrated_from_legacy` en `history`;
- existe evidencia de tipo `migration`;
- el backup referenciado por esa evidencia existe;
- `status`, `owner` y `source_channel` quedaron materializados;
- `artifacts` y `evidence` son listas.

---

## Salidas esperadas

- `diagnostics/task_audit/legacy_batch_01_quality.txt`
- `docs/TASK_LEGACY_BATCH_01_QUALITY_GATE.md`
- actualización menor de `docs/TASK_LEGACY_BASELINE_AUDIT.md`

---

## Resultado esperado

Si la quality gate sale limpia, el siguiente paso correcto sí es:

- abrir `Batch 02`

Si aparecen rarezas, primero se corrigen esas anomalías antes de escalar.

