# Arquitectura Golem

## Ontología del sistema

- Antigravity = voluntad / criterio / dirección
- OpenClaw = cuerpo operativo / interfaz / routing / tools
- Codex = obrero despertable para ejecución de tareas
- Panel del gateway = sesión canónica de control
- WhatsApp = canal secundario de lujo
- Outbox = depósito de artefactos finales

## Flujo ideal

1. Pedido entra por panel o WhatsApp.
2. OpenClaw lo normaliza en una tarea con task_id.
3. La tarea vive en la sesión canónica del panel.
4. Si hace falta trabajo de repo/código/documentos, OpenClaw despierta a Codex.
5. Codex trabaja y reporta progreso.
6. El resultado textual vuelve a la sesión canónica.
7. Si hay archivo final, va a outbox/<task_id>/.
8. OpenClaw entrega resumen por panel y opcionalmente por WhatsApp.

## Regla central

La conversación principal NO vive en WhatsApp.
WhatsApp es control remoto y canal de notificación.
