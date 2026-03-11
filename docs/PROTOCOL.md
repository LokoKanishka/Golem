# Protocolo mínimo OpenClaw <-> Codex

## task_id
Cada tarea debe tener un identificador único.

## Estados
- queued
- running
- artifact_ready
- delivered
- closed
- failed

## Contrato mínimo
Campos sugeridos:
- task_id
- origin (panel|whatsapp)
- canonical_session
- requested_by
- objective
- repo_path
- output_mode
- outbox_dir
- notify_policy

## Regla
Todo progreso serio se registra en la sesión canónica.
