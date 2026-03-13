# Tasks

Este directorio guarda tareas locales de Golem como archivos JSON.

## Convencion

- un archivo por tarea
- nombre: `<task_id>.json`
- contenido: modelo minimo definido en `docs/TASK_MODEL.md`
- las tareas nuevas pueden incluir `parent_task_id` y `depends_on` para orquestacion basica

## Nota

Los scripts de tareas de Golem leen y escriben solamente dentro de este directorio.
