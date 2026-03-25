# Resumen del cambio

**Objetivo:** Añadir una normalización determinista ligera sobre `surface_state_bundle` para reducir la variación entre ejecuciones sin cambiar la arquitectura ni el modelo de tareas.

**Archivos tocados:**
- `scripts/golem_host_describe_analyze.py` — añade `_normalize_surface_state_bundle` y la invoca desde `build_surface_state_bundle`.
- `tests/verify_surface_bundle.sh` — script de verificación ligero añadido.

**Qué estabiliza:**
- Normaliza texto visible en candidatos y ordena listas por huella determinista.
- Mantiene `source_refs` y campos de confidence intactos.

**Limitaciones conocidas:**
- La normalización es conservadora y *best-effort*; no intenta reconciliar diferencias causadas por OCR profundo.
- Las pruebas integrales (smokes) requieren un entorno gráfico (X11) y utilidades como `wmctrl` o `tesseract` — no se ejecutaron en este entorno.

**Cómo revalidar (local):**
1. Ejecutar el verify ligero:

```bash
bash tests/verify_surface_bundle.sh
```

2. Si el host dispone del entorno gráfico y utilidades necesarias, ejecutar los smokes en `tests/` para validar comparabilidad real entre capturas.

Si quieres, puedo añadir una pequeña suite de fixtures y un script que ejecute el analizador sobre muestras guardadas y compare `surface-state.json` antes/después automáticamente.
