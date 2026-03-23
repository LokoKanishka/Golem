# Minimal Task CLI: Golem

## Propósito

Este documento ya no describe un bootstrap de tareas.

Hoy define el entrypoint canonico minimo y estable del carril vigente.

---

## Entry Point Canonico

- `scripts/task_create.sh` es el entrypoint canonico para crear tareas nuevas.
- `scripts/task_new.sh` queda solo como wrapper de compatibilidad para flows viejos que todavia entregan `<type> <title>`.

La tarea resultante debe quedar estrictamente compatible con `task_validate.sh --strict` y, al mismo tiempo, cargar los campos de orquestacion que necesita el carril actual (`type`, `parent_task_id`, `depends_on`, `delivery`, `media`, `screenshot`, etc.).

---

## Principios

### 1. Repo-first
La tarea nace en el repo y Git debe verla.

### 2. Simplicidad explícita
No dejar dos entrypoints canonicos compitiendo.

### 3. Salida legible
Los comandos deben servir tanto para humanos como para automatización liviana.

### 4. Cero ficción
Si algo no está implementado, no se simula.

---

## task_create.sh

Crea una nueva tarea JSON canónica en `tasks/`.

### Uso mínimo

```bash
./scripts/task_create.sh "Título" "Objetivo"
```

### Opciones

- `--type <task_type>`
- `--owner <owner>`
- `--source <source_channel>`
- `--accept <texto>` (repetible)

### Defaults

- `type=""`
- `owner=unassigned`
- `source_channel=operator`

### Compatibilidad de orquestacion

Tambien acepta por entorno:

- `TASK_PARENT_TASK_ID`
- `TASK_DEPENDS_ON`
- `TASK_STEP_NAME`
- `TASK_STEP_ORDER`
- `TASK_CRITICAL`
- `TASK_EXECUTION_MODE`
- `TASK_CANONICAL_SESSION`
- `TASK_ORIGIN`

---

## task_new.sh

Se mantiene solo por compatibilidad:

```bash
./scripts/task_new.sh <type> <title>
```

Internamente ya delega a `task_create.sh`.

---

## task_list

Lista tareas activas de `tasks/` en formato tabular simple.

### Uso

```bash
./scripts/task_list.sh
```

### Opciones

- `--status <status>` filtra por estado canónico.

---

## task_show

Muestra una tarea completa, pretty-printed.

### Uso

```bash
./scripts/task_show.sh <task-id|path>
```

Acepta:

- id canónico, por ejemplo `task-20260320T154500Z-a1b2c3d4`
- path directo, por ejemplo `tasks/task-20260320T154500Z-a1b2c3d4.json`

---

## Verify mínimo

`verify_task_cli_minimal.sh` comprueba:

- que se puede crear una tarea canonica;
- que el archivo queda en `tasks/`;
- que `task_list` la ve;
- que `task_show` la imprime;
- que el JSON tiene estructura base esperable.

---

## Implicación

El repo ya no debe tratar `task_create.sh` y `task_new.sh` como dos verdades activas.
La verdad canonica es `task_create.sh`.
