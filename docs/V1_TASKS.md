# V1 Tasks: Golem

## Objetivo
Definir qué tareas puede resolver Golem hoy, por sí mismo, sin depender de un worker externo.

## Principio
Solo se incluyen tareas ya probadas o muy cercanas a lo ya probado.
No se promete escritorio completo ni delegación a workers en esta etapa.

---

## Tareas V1 confirmadas

### 1. Conversación operativa en panel
- responder en la sesión principal del panel
- mantener continuidad básica de conversación
- usar el panel como consola principal

### 2. Conversación auxiliar por WhatsApp
- recibir mensajes por WhatsApp
- responder por WhatsApp
- usar WhatsApp como canal remoto/auxiliar
- reflejar la sesión en el gateway

### 3. Lectura de pestaña abierta en Chrome
- detectar una pestaña correctamente adjuntada por relay
- leer el contenido accesible de la pestaña abierta
- identificar de qué trata la página

### 4. Resumen de contenido web
- resumir una página en 3, 5 o más puntos
- extraer ideas principales
- devolver una síntesis utilizable por chat

### 5. Observación del propio sistema OpenClaw
- verificar que el gateway está vivo
- verificar que WhatsApp está conectado
- verificar que el browser relay está activo
- ubicar sesiones en el panel

---

## Tareas V1 plausibles pero no cerradas

### Navegación ampliada
- abrir una URL desde el agente
- cambiar entre pestañas
- comparar dos páginas abiertas
- buscar texto puntual dentro de una página

### Entrega estructurada
- producir respuestas más formateadas
- dejar resúmenes guardados en archivo
- preparar un artefacto simple para enviar luego

---

## Tareas fuera de V1

### No incluidas todavía
- worker externo real
- delegación viva a Codex
- escritorio completo
- control GUI general del host
- pipeline de tareas con task_id
- automatización autónoma compleja
- vigilancia persistente avanzada

---

## Regla operativa de V1
Si una tarea puede resolverse con:
- chat
- sesión
- lectura de pestaña
- resumen
- observación básica del gateway

entonces pertenece a V1.

Si requiere:
- trabajo largo de repo
- ejecución estructurada
- artefactos complejos
- control de escritorio completo

entonces queda fuera de V1.
