# Host Diagnostics

Los snapshots persistentes del stack local del host se escriben aca.

- Runner: `./scripts/golem_host_diagnose.sh`
- Shortcut diario: `./scripts/golem_host_stack_ctl.sh diagnose`
- Auto-disparo por falla: `./scripts/golem_host_diagnose.sh auto --source <source> --reason <reason>`
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

El auto-disparo usa cooldown para evitar tormentas de snapshots identicos. Se puede inhibir con `GOLEM_HOST_AUTO_DIAGNOSE=0`.

Los directorios timestamped generados por el runner quedan fuera de Git por `.gitignore`.
