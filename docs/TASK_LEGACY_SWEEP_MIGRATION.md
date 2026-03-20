# Legacy Task Sweep and Migration: Golem

## Propósito

Este tramo abre el carril de barrido y migración controlada del mundo heredado.

Hasta acá Golem ya tiene un núcleo canónico funcional:

- representación de tarea;
- create/list/show;
- update/close;
- evidence/artifacts;
- validate/archive.

Pero todavía existe deuda real en `tasks/`:

- JSON corruptos;
- tareas legacy con forma vieja;
- campos no alineados con el carril canónico;
- nombres y estados que requieren normalización.

Este documento fija un carril conservador para tratar ese mundo sin romper trazabilidad.

---

## Scripts agregados

Se agregan dos scripts operativos:

- `scripts/task_scan_legacy.sh`
- `scripts/task_migrate_legacy.sh`

Y un verify específico:

- `scripts/verify_task_legacy_migration_minimal.sh`

---

## Principio central

No se hace migración mágica en masa.

La política correcta es:

1. barrer y clasificar;
2. detectar qué es canónico, qué es legacy y qué está roto;
3. migrar de a una tarea;
4. dejar backup explícito del original;
5. recién después pensar barridos de migración más grandes.

---

## task_scan_legacy

Hace un barrido y clasifica tareas como:

- `canonical`
- `legacy`
- `corrupt`
- `invalid`

### Uso

```bash
./scripts/task_scan_legacy.sh --all
./scripts/task_scan_legacy.sh --all --include-archive
./scripts/task_scan_legacy.sh <task-id|task_id|path>
```

### Regla

El scan es informativo.
Debe seguir recorriendo aunque encuentre archivos corruptos o raros.

---

## task_migrate_legacy

Migra una tarea legacy a la forma canónica mínima actual.

### Uso

```bash
./scripts/task_migrate_legacy.sh <task-id|task_id|path> [--actor <actor>] [--dry-run]
```

### Defaults de migración

Cuando el legacy no trae campos completos, la migración usa defaults razonables:

- `owner=unassigned`
- `source_channel=operator`
- `status=todo`

### Reglas

- si la tarea ya es canónica, no la reescribe;
- crea backup del JSON original antes de tocar nada;
- normaliza campos mínimos;
- agrega traza de migración en `history`;
- agrega evidencia de migración;
- alinea nombre de archivo con el `id` canónico final.

---

## Backups

Los originales se guardan en:

- `tasks/legacy_backup/`
- `tasks/archive/legacy_backup/`

según de dónde vino la tarea.

La migración nunca debe destruir el original sin antes dejar respaldo explícito.

---

## Normalización mínima

La migración intenta mapear:

- `task_id` o `id` legacy → `id` canónico
- `source` → `source_channel`
- estados legacy (`pending`, `in_progress`, `completed`, etc.) → estados canónicos
- historia vieja → historial canónico mínimo
- artifacts/evidence heredados → listas compatibles

Si no puede conservar un campo raro dentro del carril canónico, lo preserva indirectamente a través del backup y de la traza de migración.

---

## Verify mínimo

`verify_task_legacy_migration_minimal.sh` comprueba end to end que:

- se crea una tarea legacy sintética;
- el scan la detecta como legacy;
- la migración genera backup;
- el resultado nuevo valida en modo estricto;
- la historia y evidencia reflejan la migración;
- el verify limpia sus residuos.

---

## Implicación

Con este tramo cerrado, Golem ya puede empezar a atacar la deuda heredada con método.

El paso correcto después es:

- correr barrido real sobre el repo;
- clasificar corrupt/canonical/legacy;
- diseñar lote de migración por tandas pequeñas;
- recién luego reconciliar panel y WhatsApp contra tareas canónicas reales.
