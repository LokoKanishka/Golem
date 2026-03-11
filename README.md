# golem

Golem es el sistema de agencia operativa donde:

- OpenClaw = golem/orquestador/interfaz
- Codex = worker despertable
- Panel del gateway = consola principal
- WhatsApp = canal auxiliar / control remoto / alertas
- Outbox = artefactos finales

## Principios
1. La sesión canónica vive en el panel.
2. WhatsApp no es el chat principal.
3. Codex no habla solo: OpenClaw lo despierta.
4. Los artefactos van a outbox.
5. Todo cambio importante debe quedar versionado.

## Estado
Bootstrap inicial del repositorio.
