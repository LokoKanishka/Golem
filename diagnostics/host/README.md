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
- `summary.txt` sigue el mismo orden visual para que helper y snapshot se lean igual bajo estres
- `CURRENT CONTEXT` en el helper compacta `gateway_context` con `gateway_last_signal`, y `task_api_active` con `whatsapp_bridge_active`, para bajar ruido sin perder senales
- `summary.txt` deja esas mismas senales con etiquetas completas y el detalle operativo mas abajo

Cobertura smoke actual:

- `./tests/smoke_host_failure_operator_summary.sh`: valida resumen corto, helper y snapshot cuando el foco de falla cae en `whatsapp_bridge`
- `./tests/smoke_host_task_api_operator_summary.sh`: valida el mismo flujo cuando el foco de falla cae en `task_api`
- `./tests/smoke_host_gateway_context_triage.sh`: valida triage de gateway/RPC degradado con stack sano y contexto parcial
- `./tests/smoke_host_stack_startup_timeout.sh`: valida el carril de `launch_golem.sh` cuando el stack arranca pero no queda sano a tiempo
- `./tests/smoke_host_gateway_systemd_down.sh`: valida el carril del launcher cuando `openclaw-gateway.service` cae a nivel systemd y task API + bridge siguen sanos
- `./tests/smoke_host_multi_failure_triage.sh`: valida una muestra chica de fallas simultaneas (`task_api + bridge`, `gateway + bridge`, `gateway + task_api`) y deja observable la prioridad actual del triage
- `./tests/smoke_host_triage_edge_cases.sh`: valida el borde final con un caso triple (`gateway + task_api + bridge`) y un `stack_startup_timeout` mezclado con gateway explicitamente en `FAIL`
- `./tests/smoke_host_auto_diagnose_failure.sh`: valida auto-disparo y cooldown del snapshot ante falla real del stack
- `./tests/smoke_host_last_snapshot_context_layout.sh`: valida que helper y `summary.txt` sigan alineados en lectura

Todavia no se cubren todas las combinaciones posibles:

- permutaciones menos utiles del borde final, como `stack_startup_timeout` mezclado con otras fallas sin gateway explicito o triples con estados intermedios mas ruidosos

Prioridad observable actual cuando hay mas de una falla:

- `stack_startup_timeout` sigue teniendo prioridad maxima
- `task_api` prima sobre bridge y sobre un gateway explicitamente en FAIL
- un gateway explicitamente en FAIL prima sobre `whatsapp_bridge`
- si el timeout ya trae `gateway=FAIL`, `second_action` salta al gateway en vez de quedar en una recomendacion generica
- `second_action` apunta al siguiente problema real cubierto por el smoke multiple, en vez de repetir el mismo foco cuando ya hay otra falla fuerte visible

Los directorios timestamped generados por el runner quedan fuera de Git por `.gitignore`.
