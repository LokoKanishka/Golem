# Task Contract: Golem

## Propósito

Este documento define qué es una tarea en Golem, qué estados puede tener, qué evidencia debe dejar y cómo se relaciona con panel, WhatsApp, repo y futuros workers.

El objetivo es que el sistema tenga una unidad de trabajo común antes de automatizar ejecución, delegación o cierre.

---

## Definición de tarea

Una tarea es una unidad de trabajo gobernada por el repo que representa una intención operativa concreta con:

- un objetivo explícito;
- un estado verificable;
- una salida esperada;
- evidencia de ejecución;
- un cierre trazable.

Una tarea no es simplemente un mensaje, una idea o una conversación.
Una tarea existe cuando queda expresada en una forma suficientemente estable como para poder:

- ejecutarla;
- auditarla;
- retomarla;
- cerrarla honestamente.

---

## Principio central

La tarea es la unidad canónica de trabajo.

No lo son por sí solos:

- un mensaje de WhatsApp;
- una conversación en panel;
- una intuición del operador;
- una ejecución aislada sin registro.

Esos elementos pueden originar, nutrir o comentar una tarea, pero no reemplazan a la tarea como unidad de verdad operativa.

---

## Campos mínimos de una tarea

Toda tarea debe tener, como mínimo:

- `id`: identificador único;
- `title`: nombre breve y claro;
- `objective`: qué se quiere lograr;
- `status`: estado actual;
- `created_at`: fecha de creación;
- `updated_at`: última actualización;
- `owner`: quién la está llevando;
- `source_channel`: de dónde nació;
- `acceptance_criteria`: criterio de cierre;
- `evidence`: trazas, logs, salidas o referencias;
- `closure_note`: nota final de cierre, éxito o falla.

---

## Estados canónicos

Los estados canónicos iniciales de una tarea son:

- `todo`
- `running`
- `blocked`
- `done`
- `failed`
- `canceled`

### Significado de cada estado

#### `todo`
La tarea fue creada y todavía no empezó su ejecución real.

#### `running`
La tarea está siendo trabajada activamente.

#### `blocked`
La tarea no puede seguir por una dependencia real, falta de acceso, error externo o restricción operativa.

#### `done`
La tarea alcanzó su objetivo con evidencia suficiente y cierre honesto.

#### `failed`
La tarea fue ejecutada pero no logró cumplir el criterio de aceptación.

#### `canceled`
La tarea se interrumpió por decisión explícita o pérdida de pertinencia, sin que eso implique necesariamente fallo técnico.

---

## Regla de verdad del estado

El estado de la tarea debe reflejar la realidad operativa y no una impresión optimista.

Por lo tanto:

- no se marca `done` por intención;
- no se marca `done` por avance parcial;
- no se marca `done` por haber escrito código sin verificar;
- no se marca `done` por “parece que funciona”.

`done` exige criterio de aceptación cumplido y evidencia compatible con ese criterio.

---

## Criterio de aceptación

Toda tarea debe declarar cómo se considera cerrada.

El criterio de aceptación debe ser:

- concreto;
- verificable;
- proporcional al tipo de tarea;
- entendible por un humano y por un futuro worker.

Buenos criterios de aceptación:

- “el script corre y devuelve salida OK”;
- “el documento quedó creado y committeado”;
- “la reconciliación actualiza el estado esperado y deja traza auditable”;
- “la verificación oficial pasa sin FAIL”.

Malos criterios de aceptación:

- “quedó más o menos”;
- “parece estar”;
- “debería funcionar”;
- “ya lo hicimos antes”.

---

## Evidencia

Toda tarea debe poder dejar evidencia.

La evidencia puede incluir:

- logs;
- stdout/stderr;
- archivos generados;
- commits;
- diffs;
- screenshots;
- rutas concretas;
- referencias a documentos del repo;
- resultados de verify o smoke tests.

La evidencia no reemplaza el juicio, pero sin evidencia no hay cierre serio.

---

## Nota de cierre

Toda tarea cerrada debe incluir una nota de cierre.

La nota de cierre debe decir, con honestidad:

- qué se hizo;
- qué quedó validado;
- qué no quedó validado;
- si hubo límites, riesgos o deuda remanente.

La nota de cierre no debe maquillar fallos.

---

## Origen de la tarea

Una tarea puede nacer desde distintos canales:

- panel del gateway;
- WhatsApp;
- operador humano;
- script del sistema;
- futuro worker;
- proceso interno programado.

Pero, una vez creada, la tarea debe converger a la misma forma gobernada por repo.

---

## Canal versus verdad

Los canales sirven para conversar, disparar o monitorear.

La verdad operativa de la tarea no debe depender de:

- que un mensaje siga visible;
- que el chat esté abierto;
- que el operador recuerde;
- que un worker conserve contexto en memoria.

La tarea debe poder sobrevivir al canal que la originó.

---

## Owner de tarea

Toda tarea debe tener un responsable actual.

El `owner` puede ser, por ejemplo:

- `diego`
- `panel`
- `system`
- `worker:<nombre>`
- `unassigned`

El owner no define la verdad.
Define solamente quién la está llevando en este momento.

---

## Relación con futuros workers

Los workers no redefinen el contrato de tarea.

Los workers deben adaptarse a este contrato común.

Eso implica que un worker futuro, incluido Codex, debería:

- recibir tareas con objetivo claro;
- actualizar estado honestamente;
- producir evidencia;
- dejar nota de cierre;
- no auto-declarar éxito sin criterio verificable.

---

## Relación con WhatsApp

WhatsApp no es la tarea.
WhatsApp es un canal de entrada, control remoto o notificación.

Una instrucción por WhatsApp puede:

- crear una tarea;
- consultar una tarea;
- pedir estado;
- pedir resumen;
- destrabar una tarea.

Pero el canal no debe convertirse en la única memoria operativa del sistema.

---

## Relación con el panel

El panel es la consola principal de operación y supervisión.

Su función ideal respecto de tareas es:

- crear;
- listar;
- inspeccionar;
- resumir;
- seguir;
- cerrar;
- escalar.

Pero la canonicidad de la tarea debe seguir apoyándose en una representación gobernada por repo o estado estructurado equivalente.

---

## Regla de no ambigüedad

Una tarea debe intentar responder claramente estas preguntas:

- ¿qué hay que lograr?
- ¿quién la lleva?
- ¿en qué estado está?
- ¿qué evidencia existe?
- ¿qué falta para cerrarla?
- ¿por qué está bloqueada, si lo está?

Si una tarea no puede responder eso, está mal formada.

---

## Separación entre conversación y ejecución

Conversar sobre una tarea no equivale a ejecutarla.

Ejecutar algo sin registrarlo tampoco equivale a gobernar una tarea.

Por eso Golem debe mantener separados, aunque conectados:

- conversación;
- decisión;
- ejecución;
- evidencia;
- cierre.

---

## Regla de cierre honesto

Una tarea puede cerrar en `done`, `failed` o `canceled`.

Cerrar honestamente vale más que cerrar “en verde” de manera ficticia.

Un sistema serio no optimiza apariencia de éxito.
Optimiza trazabilidad y verdad operativa.

---

## Orden de prioridad

Cuando haya conflicto entre canal, memoria informal y estado estructurado, debe priorizarse:

1. evidencia verificable;
2. estado estructurado de la tarea;
3. nota de cierre;
4. conversación de panel;
5. mensajes auxiliares de canal.

---

## Implicación para la siguiente fase

Con este contrato cerrado, ya se puede diseñar después:

- representación concreta de tareas;
- lifecycle operativo;
- handoff entre operador y worker;
- verdad canónica entre panel y WhatsApp;
- políticas de artefactos y outputs.
