# Next Steps

## Etapa actual
Cierre del carril canonico de tareas completado y runtime local de WhatsApp ya endurecido para operacion sostenida sobre la misma API.

## Próximos pasos propuestos
1. Preparar un modo servicio local mas persistente para el bridge ya endurecido, sin mover todavia esta operacion al host ni abrir otra API.
2. Reducir el uso residual del wrapper `task_new.sh` hasta que todo quede sobre `task_create.sh`.
3. Endurecer verifies de integracion sobre:
   - delivery user-facing;
   - reconciliacion WhatsApp;
   - worker handoff/result loop;
   - auditoria de runtime evidence.
4. Decidir con calma si toda evidencia durable de `handoffs/` debe seguir versionada o si parte de ella conviene mover a otra politica versionada, sin volver a ocultar la operacion real.

## Enfoque inmediato recomendado
- Mantener el baseline sano y las tareas activas visibles en Git.
- Tratar `./scripts/verify_task_lane_enforcement.sh` como gate obligatorio antes de merge o cierre de tramo del carril de tareas.
- Mantener el panel leyendo tareas canonicas por `./scripts/task_panel_read.sh` hasta abrir un tramo separado de mutaciones.
- Mantener las mutaciones panel-side apoyadas en `task_panel_mutate.sh` y, por debajo, en `task_create.sh`, `task_update.sh` y `task_close.sh`.
- Mantener la superficie visible del panel sobre `task_panel_http_server.py` sin abrir una segunda interfaz de UI.
- Mantener WhatsApp real apoyado en `task_whatsapp_bridge_runtime.py`, que reutiliza `task_whatsapp_query.py`, `task_whatsapp_mutate.py` y la misma API local.
- Tratar el replay del smoke como limite honesto de verify inbound local, no como una segunda arquitectura.
- No abrir un rediseño de arquitectura en paralelo.
- Priorizar integracion y verificabilidad por encima de nuevas capas doctrinales.

## Regla
No volver a tratar el repo como bootstrap. El siguiente tramo correcto ya no es arquitectura del carril, sino estabilizacion de producto/runtime sobre el contrato que quedo cerrado.
