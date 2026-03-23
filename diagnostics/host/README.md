# Host Diagnostics

Los snapshots persistentes del stack local del host se escriben aca.

- Runner: `./scripts/golem_host_diagnose.sh`
- Shortcut diario: `./scripts/golem_host_stack_ctl.sh diagnose`
- Auto-disparo por falla: `./scripts/golem_host_diagnose.sh auto --source <source> --reason <reason>`
- Ultimo snapshot util: `./scripts/golem_host_last_snapshot.sh`
- Contenido esperado por snapshot:
  - `summary.txt`
  - `manifest.json`
  - `task_api_*.json`
  - `whatsapp_bridge_*.json`
  - `systemctl_*.txt`
  - `journal_*.txt`
  - `process_*.txt`
  - `ports_*.txt`

Cada snapshot tambien registra:

- `trigger_mode`
- `trigger_source`
- `trigger_reason`
- `trigger_requested_at_utc`
- `gateway_context`
- `gateway_last_signal`
- `suggested_first_action`
- `second_action`

El auto-disparo usa cooldown para evitar tormentas de snapshots identicos. Se puede inhibir con `GOLEM_HOST_AUTO_DIAGNOSE=0`.

Ruta rapida de lectura:

1. `./scripts/golem_host_last_snapshot.sh`
2. abrir `summary.txt`
3. si hace falta mas detalle, abrir `manifest.json`

Quick triage disponible:

- `mirar journal de task_api` cuando la falla apunta a task API o no queda activa
- `revisar healthcheck de whatsapp_bridge` cuando la falla apunta al bridge o no queda sano
- `confirmar gateway RPC antes de reiniciar stack` cuando el contexto del gateway no confirma RPC

Pulido fino del helper:

- `second_action` aparece en `./scripts/golem_host_last_snapshot.sh`
- no aparece en el resumen corto principal para no ensuciar la salida bajo estres
- sale de la misma evidencia del snapshot, con reglas chicas y auditables
- la vista rapida del helper agrupa por prioridad operativa: snapshot, contexto, hacer primero, hacer despues, leer primero y leer despues

Los directorios timestamped generados por el runner quedan fuera de Git por `.gitignore`.
