# Next Steps

## Etapa actual
Cierre de transicion del carril de tareas completado.

## Próximos pasos propuestos
1. Integrar el carril canonico de tareas con reconciliacion real contra panel/WhatsApp sin reabrir el modelo.
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
- No abrir un rediseño de arquitectura en paralelo.
- Priorizar integracion y verificabilidad por encima de nuevas capas doctrinales.

## Regla
No volver a tratar el repo como bootstrap. El siguiente tramo correcto es integracion y reconciliacion sobre el carril canonico vigente.
