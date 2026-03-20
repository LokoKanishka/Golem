# Minimal Evidence and Artifacts Flow: Golem

## Propósito

Este tramo conecta el lifecycle mínimo de tareas con evidencia operativa concreta.

Hasta ahora Golem ya puede:

- crear tareas;
- listarlas;
- mostrarlas;
- actualizarlas;
- cerrarlas.

Con este paso agrega dos piezas clave para que una tarea no sea solo estado narrado:

- evidencia estructurada;
- artifacts producidos o tocados.

---

## Scripts agregados

Se agregan dos scripts operativos:

- `scripts/task_add_evidence.sh`
- `scripts/task_add_artifact.sh`

Y un verify específico:

- `scripts/verify_task_evidence_artifacts_minimal.sh`

---

## Alcance de este tramo

Este tramo sí resuelve:

- agregar entradas estructuradas en `evidence`;
- agregar rutas en `artifacts`;
- actualizar `updated_at`;
- dejar trazabilidad en `history`;
- tolerar tareas heredadas que no tengan esos campos inicializados.

Este tramo todavía NO resuelve:

- validación formal contra schema;
- deduplicación sofisticada;
- evidencias binarias;
- snapshots automáticos;
- archivado;
- políticas de retención;
- reconciliación automática con panel o WhatsApp.

---

## Principio central

El estado de una tarea no alcanza por sí solo.

La tarea debe poder responder también:

- qué evidencia existe;
- qué artifacts produjo;
- qué traza dejó ese agregado.

---

## task_add_evidence

Agrega una entrada estructurada al array `evidence`.

### Uso

```bash
./scripts/task_add_evidence.sh <task-id|path> --type <type> --note <note> [--path <path>] [--command <command>] [--result <result>] [--actor <actor>]
```

### Campos

- `type` es obligatorio;
- `note` es obligatoria;
- `path` es opcional;
- `command` es opcional;
- `result` es opcional;
- `actor` es opcional.

### Regla

La evidencia debe ser referencia estructurada y breve.
No se usa el JSON de tarea como depósito bruto de logs gigantes.

---

## task_add_artifact

Agrega una ruta al array `artifacts`.

### Uso

```bash
./scripts/task_add_artifact.sh <task-id|path> <artifact-path> [--actor <actor>] [--note <note>]
```

### Regla

`artifacts` lista outputs o archivos relevantes producidos o tocados por la tarea.
No reemplaza a `evidence`, pero la complementa.

---

## Compatibilidad heredada

Para no romper tareas viejas o incompletas:

- si falta `evidence`, se inicializa como `[]`;
- si falta `artifacts`, se inicializa como `[]`;
- si falta `history`, se inicializa como `[]`.

Eso mantiene operativo el carril nuevo mientras sigue la migración del repositorio.

---

## Verify mínimo

`verify_task_evidence_artifacts_minimal.sh` comprueba end to end que:

- se crea una tarea;
- se agrega evidencia estructurada;
- se agrega un artifact;
- el JSON final refleja ambos cambios;
- el historial registra esas operaciones.

---

## Implicación

Con este tramo cerrado, Golem ya une:

- tarea estructurada;
- lifecycle;
- evidencia;
- artifacts.

Recién después de esto conviene abrir:

- validate against schema
- archive
- reopen
- integración y reconciliación con panel/WhatsApp
