# Host Diagnostics

Los snapshots persistentes del stack local del host se escriben aca.

- Runner: `./scripts/golem_host_diagnose.sh`
- Shortcut diario: `./scripts/golem_host_stack_ctl.sh diagnose`
- Contenido esperado por snapshot:
  - `summary.txt`
  - `manifest.json`
  - `task_api_*.json`
  - `whatsapp_bridge_*.json`
  - `systemctl_*.txt`
  - `journal_*.txt`
  - `process_*.txt`
  - `ports_*.txt`

Los directorios timestamped generados por el runner quedan fuera de Git por `.gitignore`.
