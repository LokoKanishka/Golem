# Canonical Truth Model: Golem

## Propósito

Este documento define cuál es la fuente de verdad operativa en Golem cuando intervienen:

- tareas;
- panel del gateway;
- WhatsApp;
- operador humano;
- futuros workers;
- evidencia de ejecución.

Su función es evitar ambigüedad, desincronización narrativa y cierres falsamente optimistas.

---

## Principio central

En Golem, la verdad operativa no pertenece a un canal.

La verdad operativa pertenece a la combinación de:

1. estado estructurado de la tarea;
2. evidencia verificable;
3. nota de cierre consistente con esa evidencia.

Los canales sirven para operar, consultar, disparar y resumir.
No deben convertirse en la autoridad final sobre el estado real del sistema.

---

## Regla base

La unidad canónica de trabajo es la tarea.

Por lo tanto:

- el panel no reemplaza a la tarea;
- WhatsApp no reemplaza a la tarea;
- una conversación no reemplaza a la tarea;
- una intuición del operador no reemplaza a la tarea.

Todo lo importante debe converger a una representación estructurada de tarea.

---

## Qué es canónico y qué no

### Canónico

Es canónico:

- el registro estructurado de la tarea;
- la evidencia concreta asociada;
- la nota de cierre compatible con esa evidencia.

### No canónico por sí mismo

No es canónico por sí solo:

- un mensaje de WhatsApp;
- un resumen del panel;
- una memoria informal del operador;
- un comentario aislado de un worker;
- una ejecución sin persistencia ni traza.

---

## Jerarquía de verdad

Cuando haya conflicto, la prioridad correcta es esta:

1. evidencia verificable;
2. estado estructurado de la tarea;
3. nota de cierre;
4. vista operativa del panel;
5. mensajes de WhatsApp;
6. memoria informal del operador o del worker.

---

## Qué cuenta como evidencia verificable

Se considera evidencia verificable, entre otras cosas:

- logs;
- stdout/stderr;
- archivos generados;
- commits;
- diffs;
- resultados de verify;
- resultados de smoke tests;
- rutas concretas en repo;
- snapshots;
- screenshots pertinentes;
- salidas persistidas por scripts del sistema.

La evidencia debe ser concreta y auditable.
No alcanza con “se hizo” o “debería estar”.

---

## Rol del panel

El panel del gateway es la consola principal de operación humana.

Su rol es:

- concentrar supervisión;
- mostrar estado;
- permitir seguimiento;
- resumir tareas;
- facilitar control y coordinación.

Pero el panel no debe ser tratado como fuente absoluta de verdad si no coincide con la tarea y la evidencia.

### Fórmula correcta

- panel = superficie principal de operación;
- tarea = unidad canónica;
- evidencia = árbitro final.

---

## Rol de WhatsApp

WhatsApp es un canal auxiliar y remoto.

Su rol es:

- disparar instrucciones;
- consultar estado;
- recibir notificaciones;
- pedir resúmenes;
- actuar como control remoto liviano.

WhatsApp no debe ser la memoria canónica del sistema.

### Consecuencia

Un mensaje de WhatsApp puede:

- originar una tarea;
- pedir actualización;
- pedir cierre;
- consultar estado;
- destrabar una tarea.

Pero no debe, por sí solo, definir el estado real sin reconciliación con la tarea estructurada.

---

## Rol del operador humano

El operador puede:

- crear tareas;
- actualizar tareas;
- interpretar evidencia;
- corregir estados mal asignados;
- cerrar tareas honestamente.

Pero tampoco debe imponerse contra la evidencia.
Su criterio ordena el sistema; no reemplaza la realidad operativa.

---

## Rol de futuros workers

Los workers futuros pueden:

- ejecutar;
- producir outputs;
- sugerir cambios de estado;
- adjuntar evidencia;
- proponer cierre.

Pero no deben ser tratados como autoridad incuestionable.

Toda afirmación de un worker debe terminar reconciliada contra:

- la tarea;
- la evidencia;
- el criterio de aceptación.

---

## Regla de reconciliación

Cuando un canal dice algo importante sobre una tarea, ese dato debe reconciliarse con el estado estructurado.

Ejemplos:

- si WhatsApp pide “cerrar esto”, debe evaluarse si la evidencia permite `done`;
- si el panel muestra `running` pero la verify falló, la tarea debe corregirse;
- si un worker dice “terminado” pero no hay evidencia, no corresponde `done`;
- si hay evidencia suficiente pero el panel quedó viejo, se actualiza el panel, no la realidad.

---

## Regla de retraso visual

El panel o WhatsApp pueden estar desactualizados por latencia, caché, resumen viejo o falta de refresh.

En esos casos:

- no se corrige la tarea para que coincida con la vista;
- se corrige la vista para que coincida con la tarea y la evidencia.

La interfaz puede atrasarse.
La verdad operativa no debe degradarse por eso.

---

## Verdad de creación

Una tarea puede nacer desde:

- panel;
- WhatsApp;
- operador;
- script;
- worker;
- proceso programado.

Pero una vez creada, debe obtener:

- identificador;
- estado;
- owner;
- criterio de aceptación;
- evidencia asociable;
- traza de actualización.

El origen no define la canonicidad.
La normalización sí.

---

## Verdad de estado

El estado real de una tarea surge de la mejor lectura conjunta entre:

- criterio de aceptación;
- evidencia;
- última actualización seria;
- nota de cierre, si existe.

No surge de:
- el canal más reciente;
- el mensaje más enfático;
- la interfaz más visible;
- el actor más optimista.

---

## Verdad de cierre

Una tarea solo puede considerarse realmente cerrada cuando:

- su estado estructurado fue actualizado;
- existe evidencia suficiente;
- la nota de cierre refleja honestamente el resultado.

Esto aplica tanto para `done` como para `failed` o `canceled`.

---

## Casos de conflicto

### Caso A: WhatsApp dice “ya está”
Si no hay evidencia ni actualización estructurada, la tarea no está cerrada.

### Caso B: el panel muestra `done` pero la verify falla
La tarea debe corregirse a `failed` o `running`, según corresponda.

### Caso C: el worker afirma éxito pero no dejó artefactos
No corresponde `done` todavía.

### Caso D: existe commit, verify OK y nota de cierre, pero el panel sigue viejo
La verdad es el cierre estructurado; el panel debe reconciliarse.

### Caso E: el operador recuerda otra cosa pero no hay traza
Se prioriza lo verificable.

---

## Política de resúmenes

Los resúmenes en panel o WhatsApp deben entenderse como vistas derivadas.

Eso significa que:

- pueden condensar;
- pueden omitir detalle;
- pueden simplificar contexto.

Pero no deben reemplazar el estado base de la tarea.

---

## Política de comandos remotos

Los comandos remotos desde WhatsApp o canales auxiliares deben interpretarse como:

- intención;
- solicitud;
- instrucción operativa;
- consulta.

No como mutación canónica automática, salvo que el sistema implemente explícitamente esa transición con persistencia y evidencia.

---

## Regla de persistencia

Todo dato importante que afecte el trabajo real debe terminar persistido fuera del canal efímero.

Especialmente:

- creación de tareas;
- cambios de estado;
- bloqueos;
- cierres;
- evidencia;
- artefactos;
- resultados de verify.

Si no persiste, el sistema queda rehén del chat.

---

## Regla anti-ilusión

Golem no debe parecer ordenado.
Debe estar ordenado.

Por eso:

- no se privilegia la interfaz sobre la realidad;
- no se privilegia el último mensaje sobre la evidencia;
- no se privilegia el entusiasmo del actor sobre el criterio de aceptación;
- no se privilegia la memoria oral sobre la traza durable.

---

## Fórmula canónica resumida

La fórmula correcta de verdad en Golem es:

- tarea estructurada = verdad de trabajo;
- evidencia = árbitro de realidad;
- panel = consola principal;
- WhatsApp = canal auxiliar;
- resúmenes = vistas derivadas.

---

## Implicación inmediata

Con este modelo cerrado, el siguiente paso correcto es fijar la representación concreta de la tarea en el repo.

Eso implica decidir, de forma explícita:

- dónde vive una tarea;
- en qué formato;
- cómo se actualiza;
- cómo se listan estados;
- cómo se adjunta evidencia;
- cómo se refleja luego en panel y WhatsApp.
