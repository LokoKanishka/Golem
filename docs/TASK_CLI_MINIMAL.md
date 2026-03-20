# Minimal Task CLI: Golem

## Propósito

Este tramo introduce el primer carril operativo mínimo para tareas canónicas en repo.

No intenta resolver todavía:

- updates complejos;
- cierre;
- archivado;
- reconciliación con panel;
- integración con WhatsApp;
- concurrencia;
- validación formal contra schema externo.

Su objetivo es mucho más básico y más importante en esta etapa:

- crear tareas reales;
- listarlas;
- inspeccionarlas;
- dejar una interfaz estable y simple para crecer después.

---

## Scripts iniciales

Se agregan tres scripts mínimos:

- `scripts/task_create.sh`
- `scripts/task_list.sh`
- `scripts/task_show.sh`

Y un verify básico:

- `scripts/verify_task_cli_minimal.sh`

---

## Principios

### 1. Repo-first
La tarea nace en el repo, no en una vista efímera.

### 2. Simplicidad explícita
No se agregan features “inteligentes” todavía.

### 3. Salida legible
Los comandos deben servir tanto para humanos como para automatización liviana.

### 4. Cero ficción
Si algo no está implementado, no se simula.

---

## task_create

Crea una nueva tarea JSON en `tasks/`.

### Uso mínimo

```bash
./scripts/task_create.sh "Título" "Objetivo"
```

### Opciones

- `--owner <owner>`
- `--source <source_channel>`
- `--accept <texto>` (repetible)

### Defaults

- `owner=unassigned`
- `source_channel=operator`

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

- que se puede crear una tarea;
- que el archivo queda en `tasks/`;
- que `task_list` la ve;
- que `task_show` la imprime;
- que el JSON tiene estructura base esperable.

Este verify no reemplaza validación de schema completa.
Solo demuestra que el carril mínimo existe y funciona.

---

## Implicación

Con este tramo cerrado, recién después tiene sentido agregar:

- `task_update`
- `task_close`
- `task_add_evidence`
- validación contra schema
- integración con panel/WhatsApp
