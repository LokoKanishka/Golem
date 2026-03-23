# State

`state/` no gobierna runtime vivo.

Semantica actual:

- `state/live/` guarda snapshots de evidencia local sobre el entorno o el gateway;
- sirve para auditoria, debugging y referencia historica;
- no debe leerse como fuente canonica de configuracion ni como modulo activo del servicio.

En particular:

- `state/live/openclaw/` contiene capturas o estados observados de OpenClaw;
- `state/live/system/` contiene snapshots puntuales de systemd/journal;
- estos archivos pueden quedar viejos sin que el repo este roto.

La verdad operativa del carril de tareas vive en `tasks/`, no en `state/`.
