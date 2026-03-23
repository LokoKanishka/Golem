# Task Legacy Baseline Audit: Golem

## Timestamp

- generated_at_utc: `2026-03-23T04:30:55Z`

## Scope

- `tasks/` active inventory
- `tasks/archive/` archived inventory
- raw outputs saved under `diagnostics/task_audit/`

## Active Tasks

- canonical: 1395
- legacy: 0
- corrupt: 0
- invalid: 0

`SCAN_SUMMARY total=1395 canonical=1395 legacy=0 corrupt=0 invalid=0`

### Legacy

- none

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

- canonical: 1395
- legacy: 0
- corrupt: 0
- invalid: 0

`SCAN_SUMMARY total=1395 canonical=1395 legacy=0 corrupt=0 invalid=0`

## Reading

- `canonical` ya está en carril nuevo.
- `legacy` puede migrarse con el carril conservador actual.
- `corrupt` requiere atención prioritaria porque ni siquiera parsea.
- `invalid` requiere revisión puntual porque parsea pero no encaja bien.

## Next Step

La próxima acción correcta es mantener el inventario sano y pasar a reconciliación con panel/WhatsApp, porque ya no quedan `legacy` ni `corrupt`.

1. sostener validate/archive;
2. vigilar regresiones;
3. avanzar sobre integración y reconciliación.

