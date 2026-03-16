# Next Steps

## Etapa actual
Fundación del repositorio y baseline del sistema vivo.

## Próximos pasos propuestos
1. Definir modelo de tareas de Golem sin asumir integración viva con Codex.
2. Definir qué puede hacer OpenClaw hoy por sí mismo.
3. Separar:
   - capacidades actuales
   - capacidades futuras
   - capacidades deseadas
4. Recién después decidir:
   - si Codex entra por ACP, exec o wrapper
   - qué rol exacto cumple
   - qué eventos deben dispararlo

## Enfoque inmediato recomendado (user-facing)
- Implementar la cola priorizada en `docs/USER_FACING_DELIVERY_BACKLOG.md` empezando por P0.
- No cerrar tareas como exitosas si no hay evidencia de entrega visible al usuario.
- Tratar WhatsApp como canal con niveles de certeza explícitos.

## Regla
Antes de integrar workers, fijar doctrina y contrato del sistema.
