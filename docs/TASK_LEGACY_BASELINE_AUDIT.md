# Task Legacy Baseline Audit: Golem

## Timestamp

- generated_at_utc: `2026-03-23T04:10:29Z`

## Scope

- `tasks/` active inventory
- `tasks/archive/` archived inventory
- raw outputs saved under `diagnostics/task_audit/`

## Active Tasks

- canonical: 1385
- legacy: 10
- corrupt: 0
- invalid: 0

`SCAN_SUMMARY total=1395 canonical=1385 legacy=10 corrupt=0 invalid=0`

### Legacy

- `TASK_SCAN_LEGACY task-20260320T002755Z-1232e1c1 /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T002755Z-1232e1c1.json`
- `TASK_SCAN_LEGACY task-20260320T002755Z-46c5b88c /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T002755Z-46c5b88c.json`
- `TASK_SCAN_LEGACY task-20260320T002755Z-dcf710d9 /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T002755Z-dcf710d9.json`
- `TASK_SCAN_LEGACY task-20260320T003923Z-f2a179cb /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T003923Z-f2a179cb.json`
- `TASK_SCAN_LEGACY task-20260320T004502Z-683789eb /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004502Z-683789eb.json`
- `TASK_SCAN_LEGACY task-20260320T004502Z-b00b8aca /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004502Z-b00b8aca.json`
- `TASK_SCAN_LEGACY task-20260320T004502Z-b8b47720 /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004502Z-b8b47720.json`
- `TASK_SCAN_LEGACY task-20260320T004636Z-5d48b885 /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004636Z-5d48b885.json`
- `TASK_SCAN_LEGACY task-20260320T004636Z-66229532 /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004636Z-66229532.json`
- `TASK_SCAN_LEGACY task-20260320T004636Z-c5e6e27a /home/lucy-ubuntu/Escritorio/golem/tasks/task-20260320T004636Z-c5e6e27a.json`

### Corrupt

- none

### Invalid

- none

## Archive Tasks

- canonical: 0
- legacy: 0
- corrupt: 0
- invalid: 0

`SCAN_SUMMARY total=0 canonical=0 legacy=0 corrupt=0 invalid=0`

### Legacy

- none

### Corrupt

- none

### Invalid

- none

## Combined Totals

- canonical: 1385
- legacy: 10
- corrupt: 0
- invalid: 0

`SCAN_SUMMARY total=1395 canonical=1385 legacy=10 corrupt=0 invalid=0`

## Reading

- `canonical` ya está en carril nuevo.
- `legacy` puede migrarse con el carril conservador actual.
- `corrupt` requiere atención prioritaria porque ni siquiera parsea.
- `invalid` requiere revisión puntual porque parsea pero no encaja bien.

## Next Step

La próxima acción correcta es continuar con migración legacy controlada en tandas chicas o moderadas, porque el carril activo ya no tiene `corrupt`.

1. seguir con batches auditables;
2. validar cada lote en estricto;
3. rerun del baseline después de cada tanda.

