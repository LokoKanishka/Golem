# Task Trace Gap Note

## Hallazgo

La diferencia observada al revisar `batch_15` no se debe a una doble migracion dentro del lote.

Los artefactos del batch son consistentes con una corrida de 100 tareas:

- 100 candidatas;
- 100 migradas;
- 100 validadas;
- 0 duplicados relevantes.

## Causa real

El desfasaje de lectura proviene de que las tareas activas `tasks/task-*.json` estan ignoradas por Git a nivel local (`.git/info/exclude`).

Consecuencias:

- el estado operativo real si avanzo;
- el baseline real si refleja ese avance;
- pero el diff/commit de Git no muestra la mutacion de las tareas activas, solo backups y diagnosticos.

## Conclusion operativa

Se toma como fuente de verdad operativa el baseline real vigente:

- canonical: 1385
- legacy: 10
- corrupt: 0
- invalid: 0

No hay evidencia de que `batch_15` haya ejecutado 200 migraciones.
La evidencia apunta a una corrida normal de 100 sobre un estado operativo ya adelantado.

## Siguiente paso correcto

Cerrar el inventario legacy activo restante con un lote final de 10,
y despues decidir si conviene corregir la politica de trazabilidad de `tasks/task-*.json`.
