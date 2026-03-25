Resumen corto del cambio

Objetivo: Añadir una normalización determinista ligera sobre `surface_state_bundle`
para reducir variación entre corridas sin cambiar arquitectura ni modelo de tareas.

Archivos tocados:
- `scripts/golem_host_describe_analyze.py` — añade `_normalize_surface_state_bundle` y la invoca desde `build_surface_state_bundle`.
- `tests/verify_surface_bundle.sh` — verify ligero añadido.

Qué estabiliza:
- normaliza texto visible en candidatos y ordena listas por huella determinista
- mantiene `source_refs` y campos de confidence intactos

Limitaciones conocidas:
- normalización es conservadora y best-effort; no intenta reconciliar diferencias por OCR profundo
- smokes completas pueden requerir entorno gráfico (X11, wmctrl, tesseract) — no fueron ejecutadas aquí

Cómo revalidar (local):
1. `bash tests/verify_surface_bundle.sh`
2. ejecutar los smoke scripts bajo `tests/` si el host tiene X11 y herramientas instaladas
