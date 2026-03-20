# Legacy Task Batch Runner

## Propósito

Este tramo reemplaza la proliferación de scripts específicos por batch
(`batch_01`, `batch_02`, etc.) por un runner parametrizable.

La idea es simple:

- no duplicar lógica;
- no llenar el repo de scripts casi idénticos;
- poder correr tandas controladas con:
  - etiqueta,
  - tamaño de lote,
  - actor.

---

## Uso

```bash
./scripts/task_migrate_legacy_batch.sh --label batch_03 --count 50 --actor system
```

### Parámetros

- `--label <label>`: nombre lógico del lote, por ejemplo `batch_03`
- `--count <n>`: cantidad de tareas legacy a migrar
- `--actor <actor>`: actor de la migración
- `--scan-file <path>`: opcional, default `diagnostics/task_audit/active_scan.txt`

---

## Artefactos por corrida

Cada corrida genera:

- `diagnostics/task_audit/legacy_<label>_candidates.txt`
- `diagnostics/task_audit/legacy_<label>_dry_run.txt`
- `diagnostics/task_audit/legacy_<label>_migrated.txt`
- `diagnostics/task_audit/legacy_<label>_validate.txt`

---

## Regla

El runner:

1. selecciona tareas `legacy` del scan activo;
2. toma las primeras `N`;
3. hace dry-run completo;
4. migra una por una;
5. valida cada migrada en `--strict`;
6. corta si algo falla.

---

## Implicación

Con este runner cerrado, los próximos lotes dejan de ser trabajo artesanal y pasan a ser una operación repetible y auditable.
