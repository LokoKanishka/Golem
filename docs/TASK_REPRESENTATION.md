# Task Representation in Repo: Golem

## Propósito

Este documento fija la representación concreta de una tarea dentro del repo.

Hasta acá ya quedaron definidos:

- el modelo operativo;
- el contrato general de tarea;
- la verdad canónica entre tarea, panel y WhatsApp.

Ahora se define cómo vive una tarea de forma material y auditable en Golem.

---

## Principio central

La tarea canónica debe existir como archivo estructurado dentro del repo.

La forma inicial elegida es:

- un archivo JSON por tarea;
- almacenado en `tasks/`;
- con esquema estable;
- con identificador único;
- con historial de actualizaciones;
- con referencias a evidencia y artefactos.

---

## Ubicación

Las tareas activas viven en:

- `tasks/`

Las tareas cerradas o retiradas podrán, más adelante, archivarse en:

- `tasks/archive/`

---

## Formato

El formato inicial canónico es JSON.

Razones:

- fácil de parsear;
- fácil de validar;
- apto para scripts;
- entendible por humanos;
- compatible con paneles, workers y procesos futuros.

---

## Convención de nombre de archivo

La convención base será:

`tasks/task-<timestamp>-<shortid>.json`

Ejemplo:

`tasks/task-20260320T154500Z-a1b2c3d4.json`

### Regla

- `timestamp` en UTC, formato compacto;
- `shortid` para evitar colisiones y permitir referencia corta;
- el nombre de archivo no reemplaza al campo `id`, pero debe alinearse con él.

---

## Regla de identidad

Cada tarea debe tener:

- `id` único global dentro del repo;
- nombre de archivo consistente con ese `id`.

Ejemplo:

- archivo: `tasks/task-20260320T154500Z-a1b2c3d4.json`
- `id`: `task-20260320T154500Z-a1b2c3d4`

---

## Estructura mínima

Toda tarea debe contener, como mínimo, estos campos:

- `id`
- `title`
- `objective`
- `status`
- `owner`
- `source_channel`
- `created_at`
- `updated_at`
- `acceptance_criteria`
- `evidence`
- `artifacts`
- `closure_note`
- `history`

---

## Significado de los campos

### `id`
Identificador único de la tarea.

### `title`
Nombre corto y claro.

### `objective`
Descripción concreta de lo que se quiere lograr.

### `status`
Estado actual canónico.

Valores iniciales permitidos:

- `todo`
- `running`
- `blocked`
- `done`
- `failed`
- `canceled`

### `owner`
Responsable actual.

Ejemplos:

- `diego`
- `system`
- `panel`
- `worker:codex`
- `worker:future`
- `unassigned`

### `source_channel`
Canal de origen.

Ejemplos:

- `panel`
- `whatsapp`
- `operator`
- `script`
- `worker`
- `scheduled_process`

### `created_at`
Fecha/hora de creación en ISO 8601 UTC.

### `updated_at`
Última fecha/hora de actualización seria en ISO 8601 UTC.

### `acceptance_criteria`
Lista de condiciones concretas para considerar cierre válido.

### `evidence`
Lista de evidencias verificables.

Cada entrada puede incluir cosas como:

- tipo;
- descripción;
- ruta;
- comando;
- resultado;
- nota breve.

### `artifacts`
Lista de archivos o salidas producidas por la tarea.

### `closure_note`
Nota final de cierre.

Puede estar vacía mientras la tarea no esté cerrada.

### `history`
Historial de eventos relevantes de la tarea.

---

## Estructura sugerida de `history`

Cada evento de historial debería incluir, como mínimo:

- `at`
- `actor`
- `action`
- `note`

Ejemplo conceptual:

- creación;
- cambio de estado;
- bloqueo;
- agregado de evidencia;
- cierre;
- corrección de cierre.

---

## Regla de historial

El historial no reemplaza el estado actual.

Su función es:

- dejar traza;
- explicar transiciones;
- permitir auditoría;
- evitar que el sistema dependa de memoria oral.

---

## Regla de evidencia

La evidencia debe ir como referencias estructuradas, no como blobs gigantes embebidos.

Correcto:

- rutas a archivos;
- resumen de salida;
- referencia a commit;
- referencia a verify;
- snapshot puntual;
- log path.

Incorrecto como práctica general:

- pegar logs enormes enteros dentro del JSON;
- meter archivos binarios dentro de la tarea;
- usar la tarea como depósito bruto de datos.

---

## Regla de artefactos

`artifacts` debe listar outputs producidos o tocados por la tarea.

Ejemplos:

- documentos creados;
- scripts agregados;
- archivos de salida;
- rutas relevantes;
- reportes generados.

Esto ayuda a distinguir:

- evidencia de que algo pasó;
- artefactos que quedaron como resultado.

---

## Regla de cierre

Cuando `status` pase a:

- `done`
- `failed`
- `canceled`

debe existir una `closure_note` no vacía y al menos una base razonable de evidencia o justificación.

---

## Regla de actualización

Toda actualización seria de una tarea debe:

- tocar `updated_at`;
- dejar entrada en `history`;
- mantener consistencia entre `status`, `closure_note` y `evidence`.

---

## Regla de no contradicción

No debe quedar una tarea con combinaciones absurdas, por ejemplo:

- `status = done` y `closure_note = ""`
- `status = done` sin evidencia ni criterio cumplido
- `status = todo` con nota de cierre final
- `status = failed` pero historial solo de éxito
- `status = blocked` sin nota que explique el bloqueo

---

## Ejemplo canónico mínimo

```json
{
  "id": "task-20260320T154500Z-a1b2c3d4",
  "title": "Definir representación de tareas en repo",
  "objective": "Fijar formato, ubicación y esquema JSON para tareas canónicas de Golem.",
  "status": "done",
  "owner": "diego",
  "source_channel": "operator",
  "created_at": "2026-03-20T15:45:00Z",
  "updated_at": "2026-03-20T16:10:00Z",
  "acceptance_criteria": [
    "Existe un documento que fija la representación concreta de tareas.",
    "Existe un esquema JSON inicial para validar tareas.",
    "La convención de ubicación y naming quedó definida."
  ],
  "evidence": [
    {
      "type": "doc",
      "path": "docs/TASK_REPRESENTATION.md",
      "note": "Documento de representación creado."
    },
    {
      "type": "schema",
      "path": "schemas/task.schema.json",
      "note": "Esquema inicial agregado."
    }
  ],
  "artifacts": [
    "docs/TASK_REPRESENTATION.md",
    "schemas/task.schema.json"
  ],
  "closure_note": "Se fijó la representación canónica inicial de tareas en repo.",
  "history": [
    {
      "at": "2026-03-20T15:45:00Z",
      "actor": "diego",
      "action": "created",
      "note": "Tarea creada."
    },
    {
      "at": "2026-03-20T16:10:00Z",
      "actor": "diego",
      "action": "closed_done",
      "note": "Representación y esquema inicial definidos."
    }
  ]
}
```

---

## Decisión importante

En esta fase, el repo es la verdad estructurada.

Panel y WhatsApp deberán leer, resumir o mutar esta representación de manera reconciliada.
No al revés.

---

## Lo que todavía NO se define acá

Este documento no fija todavía:

- scripts de creación automática;
- comandos CLI;
- reconciliación automática con panel o WhatsApp;
- archivado automático;
- locks o concurrencia;
- vistas derivadas.

Eso corresponde al siguiente tramo.

---

## Implicación inmediata

Con esta representación cerrada, el siguiente paso correcto es crear:

- el esquema JSON oficial;
- un ejemplo real de tarea;
- luego scripts mínimos de create / list / update / close.
