# Minimal Task Validate and Archive Flow: Golem

## Propósito

Este tramo agrega dos capacidades de higiene operativa al sistema de tareas:

- validación mínima de tareas;
- archivado trazable de tareas cerradas.

Hasta acá Golem ya puede:

- crear tareas;
- listarlas;
- mostrarlas;
- actualizarlas;
- cerrarlas;
- adjuntar evidencia;
- adjuntar artifacts.

Con este paso agrega control de consistencia y retiro ordenado del carril activo.

---

## Scripts agregados

Se agregan dos scripts operativos:

- `scripts/task_validate.sh`
- `scripts/task_archive.sh`

Y un verify específico:

- `scripts/verify_task_validate_archive_minimal.sh`

---

## Alcance de este tramo

Este tramo sí resuelve:

- validar tareas individuales;
- validar todas las tareas activas;
- tolerar tareas legacy en modo no estricto;
- detectar JSON corrupto sin tumbar el recorrido completo;
- archivar tareas cerradas en `tasks/archive/`;
- dejar traza de archivado en `history`.

Este tramo todavía NO resuelve:

- migración automática de legacy a canónico;
- reparación automática de JSON corrupto;
- deduplicación fuerte;
- retention policies;
- re-open;
- reconciliación automática con panel o WhatsApp.

---

## Principio central

Un sistema serio no solo crea y cierra tareas.

También necesita:

- comprobar qué está sano y qué no;
- retirar del carril activo lo que ya terminó;
- hacerlo con reglas explícitas y auditable.

---

## task_validate

Valida tareas canónicas y tolera compatibilidad heredada en modo no estricto.

### Uso

```bash
./scripts/task_validate.sh <task-id|path>
./scripts/task_validate.sh --all
```

### Opciones

- `--strict`
- `--include-archive`

### Reglas

#### Modo normal

- valida tareas canónicas;
- acepta tareas legacy compatibles con warning;
- reporta JSON corrupto como fail;
- sigue recorriendo aunque encuentre errores.

#### Modo estricto

- exige forma canónica mínima;
- tareas legacy pasan a fail;
- útil para carriles nuevos y verify.

---

## task_archive

Mueve una tarea fuera de `tasks/` hacia `tasks/archive/`.

### Uso

```bash
./scripts/task_archive.sh <task-id|path> [--actor <actor>] [--note <note>] [--force]
```

### Reglas

Por defecto solo archiva tareas con estado terminal canónico:

- `done`
- `failed`
- `canceled`

Además, para no romper el carril heredado, tolera `blocked` como estado legacy archivable.

Con `--force` puede archivarse igual, pero esa vía debe usarse con criterio.

---

## Trazabilidad de archivado

Antes de mover el archivo, el script:

- actualiza `updated_at`;
- agrega una entrada `archived` en `history`;
- conserva el resto del contenido;
- mueve el JSON a `tasks/archive/`.

---

## Compatibilidad heredada

En tareas incompletas o viejas:

- si falta `history`, se inicializa como `[]`;
- si falta `updated_at`, se completa en el momento del archivado;
- la validación normal puede marcarlas como `legacy-compatible`.

Eso permite migrar por etapas sin frenar el carril nuevo.

---

## Verify mínimo

`verify_task_validate_archive_minimal.sh` comprueba end to end que:

- se crea una tarea nueva;
- se valida en modo estricto;
- se cierra en `done`;
- se archiva correctamente;
- el JSON archivado conserva `closure_note` e historial;
- el verify limpia los archivos de prueba para no ensuciar el repo.

---

## Implicación

Con este tramo cerrado, Golem ya tiene:

- tarea estructurada;
- lifecycle mínimo;
- evidencia y artifacts;
- validación básica;
- archivado trazable.

El siguiente paso correcto ya pasa a ser ordenar el mundo heredado:

- barrido de validación total;
- carril de migración legacy;
- luego reconciliación con panel y WhatsApp.
