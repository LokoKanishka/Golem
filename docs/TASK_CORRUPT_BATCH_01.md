# Corrupt Task Batch 01: Initial Probe

## Propósito

Este tramo no intenta reparar todavía los JSON corruptos del inventario.

Su objetivo es más básico y más importante:

- identificar exactamente cuáles son los 4 archivos corruptos;
- capturar el error real de parseo de cada uno;
- guardar una muestra útil del contenido bruto;
- dejar una base auditable para decidir luego si conviene:
  - reparar,
  - reconstruir,
  - aislar,
  - o descartar.

---

## Regla de este tramo

En este paso NO se hace migración ni reescritura automática.

Solo se hace:

1. extracción de paths corruptos desde el baseline real;
2. intento de parseo con detalle de excepción;
3. captura de metadatos mínimos;
4. muestra inicial del contenido;
5. consolidación en reportes bajo `diagnostics/task_audit/corrupt_probe/`.

---

## Artefactos esperados

- `diagnostics/task_audit/corrupt_paths.txt`
- `diagnostics/task_audit/corrupt_probe/<archivo>.probe.txt`
- `docs/TASK_CORRUPT_BATCH_01.md`

---

## Qué debe responder este probe

Para cada corrupto debe quedar claro:

- path exacto;
- si el archivo existe;
- tamaño en bytes;
- error exacto de parseo JSON;
- primer tramo legible del contenido;
- una impresión inicial sobre si parece:
  - truncado,
  - mezclado,
  - vacío,
  - o con estructura salvageable.

---

## Implicación

Con este probe cerrado, el siguiente paso correcto será abrir la primera tanda real de tratamiento:

- reparar los corruptos salvageables;
- aislar los irrecuperables;
- recién después volver a legacy migrable normal.

