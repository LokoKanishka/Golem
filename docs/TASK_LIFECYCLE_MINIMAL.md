# Minimal Task Lifecycle: Golem

## Propósito

Este tramo completa el ciclo de vida mínimo de una tarea canónica en repo.

Hasta ahora el sistema ya puede:

- crear tareas;
- listarlas;
- mostrarlas.

Con este paso agrega lo mínimo necesario para gobernar una tarea de verdad:

- actualizar campos relevantes;
- mover estado de forma explícita;
- cerrar una tarea con nota honesta.

---

## Scripts agregados

Se agregan dos scripts operativos:

- `scripts/task_update.sh`
- `scripts/task_close.sh`

Y un verify de lifecycle:

- `scripts/verify_task_lifecycle_minimal.sh`

---

## Alcance de este tramo

Este tramo sí resuelve:

- cambios básicos de estado;
- cambio de owner;
- cambio de título u objetivo;
- agregado simple de criterios de aceptación;
- cierre en `done`, `failed` o `canceled`;
- persistencia de `closure_note`;
- trazabilidad en `history`.

Este tramo todavía NO resuelve:

- adjuntar evidencia estructurada;
- agregar artifacts;
- reopen;
- archive;
- validación formal contra schema;
- locks/concurrencia;
- reconciliación automática con panel/WhatsApp.

---

## Principio central

Una tarea no se gobierna solo por existencia.
Se gobierna por transiciones explícitas y trazables.

Eso implica que cada actualización seria debe:

- tocar `updated_at`;
- dejar entrada en `history`;
- mantener coherencia entre `status`, `closure_note` y contenido.

---

## task_update

Actualiza una tarea existente sin cerrarla necesariamente.

### Uso base

```bash
./scripts/task_update.sh <task-id|path> [opciones]
```

### Opciones

- `--status <todo|running|blocked|done|failed|canceled>`
- `--owner <owner>`
- `--title <title>`
- `--objective <objective>`
- `--source <source_channel>`
- `--append-accept <texto>` (repetible)
- `--note <nota>`
- `--actor <actor>`

### Regla

`task_update` sirve para mutaciones serias del estado o metadatos.
No reemplaza el cierre final cuando corresponde fijar `closure_note`.

---

## task_close

Cierra una tarea en uno de los estados terminales permitidos.

### Uso

```bash
./scripts/task_close.sh <task-id|path> <done|failed|canceled> --note "nota de cierre"
```

### Opciones

- `--note <nota obligatoria>`
- `--actor <actor>`
- `--owner <owner>` (opcional, si el cierre reasigna owner final)

### Reglas

- solo permite estados terminales;
- exige nota de cierre no vacía;
- persiste `closure_note`;
- agrega evento final en `history`;
- no intenta “embellecer” un cierre sin justificación.

---

## Regla de cierre honesto

Cerrar una tarea significa dejar claro:

- qué pasó;
- cómo terminó;
- qué quedó efectivamente logrado o no;
- por qué el estado terminal elegido es correcto.

No sirve cerrar con notas vacías o ambiguas.

---

## Verify mínimo de lifecycle

`verify_task_lifecycle_minimal.sh` comprueba end to end que:

- una tarea se crea;
- pasa a `running`;
- actualiza owner y acceptance criteria;
- luego se cierra en `done`;
- el JSON final conserva historia y closure note coherentes.

---

## Implicación

Con este tramo cerrado, Golem ya tiene el lifecycle mínimo real de tarea:

- create
- list
- show
- update
- close

Recién después de esto conviene abrir:

- `task_add_evidence`
- `task_add_artifact`
- `task_archive`
- validate against schema
- reconciliación con panel/WhatsApp
