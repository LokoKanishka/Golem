# User-Facing Delivery Backlog

Objetivo: cerrar la brecha entre "tarea ejecutada internamente" y "resultado visible/confiable para la persona".

## Prioridad P0 (bloquea confianza)

### GOLEM-201 — Modelo de verdad de entrega
**Problema**
El estado actual no separa de forma estricta aceptación técnica vs. entrega real al usuario.

**Cambio**
- Extender el ciclo de estados de entrega con:
  - `submitted`
  - `accepted`
  - `delivered`
  - `visible`
  - `verified_by_user`
- Registrar transiciones con `timestamp`, `actor`, `evidence` y `channel`.
- Prohibir mensajes finales de éxito si el estado no alcanzó al menos `visible`.

**Criterios de aceptación**
- Una tarea de notificación no puede cerrar como `done` en UI si queda en `accepted` o `delivered` sin evidencia.
- Existe traza auditable por task id con todas las transiciones.

---

### GOLEM-202 — Entrega de artifacts a rutas visibles de usuario
**Problema**
`outbox/manual/` sirve como staging interno, pero no garantiza visibilidad en sesión gráfica del usuario.

**Cambio**
- Crear resolución canónica de rutas visibles:
  - `Desktop` / `Escritorio`
  - `Downloads` / `Descargas`
- Soportar variaciones por SO, locale y entorno de escritorio.
- Añadir verificación posterior a la copia/movimiento (`exists`, `readable`, `owner`, `path_normalized`).

**Criterios de aceptación**
- El sistema responde con ruta absoluta final y evidencia de verificación.
- Si no se puede verificar visibilidad, responder `blocked` (no `success`).

---

### GOLEM-203 — Política de claims de WhatsApp
**Problema**
El canal puede aceptar un envío sin confirmar recepción/lectura real.

**Cambio**
- Definir semántica estricta de claims:
  - "solicitado"
  - "aceptado por gateway"
  - "entregado"
  - "confirmado por usuario"
- Bloquear texto "enviado"/"listo" cuando sólo hay aceptación técnica.
- Exponer evidencia por `message_id` y proveedor.

**Criterios de aceptación**
- Mensajes de estado al usuario no confunden aceptación con entrega.
- Toda respuesta de WhatsApp incluye nivel de certeza explícito.

## Prioridad P1 (calidad de outcome)

### GOLEM-204 — Pipeline formal de media ingestion (YouTube/web/video)
**Problema**
La extracción y resumen de media no está modelada como capability robusta.

**Cambio**
- Definir capability `media_ingest_summary` con etapas:
  1) adquisición de fuente,
  2) transcript primario,
  3) fallback de transcript,
  4) resumen estructurado,
  5) artifact final.
- Estandarizar formato de salida (resumen ejecutivo, puntos clave, citas temporales cuando existan).

**Criterios de aceptación**
- Mínimo 3 fixtures de URLs con resultado reproducible.
- Respuesta final incluye fuente, método usado y nivel de confianza.

---

### GOLEM-205 — Capability explícita de screenshot/visión host-side
**Problema**
No hay contrato claro de si Golem puede o no observar escritorio host.

**Cambio**
- Declarar capability como:
  - `available`, o
  - `not_available` con fallback oficial.
- Si está disponible, definir permisos, formato de evidencia y límites de privacidad.

**Criterios de aceptación**
- El sistema nunca "simula" visión cuando no existe.
- Toda petición de "mirar pantalla" devuelve respuesta honesta y accionable.

## Prioridad P2 (operación)

### GOLEM-206 — Matriz de verificación user-facing
**Problema**
La matriz actual favorece browser/task internos y no cubre completamente "prueba de entrega percibida".

**Cambio**
- Agregar pruebas end-to-end orientadas a usuario:
  - archivo visible en carpeta esperada,
  - claim de WhatsApp con nivel de certeza,
  - diferencia explícita entre `accepted` y `verified_by_user`.

**Criterios de aceptación**
- Cada capability user-facing tiene caso PASS/FAIL/BLOCKED.
- Reporte semanal muestra tasa de tareas cerradas sin `verified_by_user`.

## Orden de ejecución recomendado
1. GOLEM-201
2. GOLEM-202
3. GOLEM-203
4. GOLEM-204
5. GOLEM-205
6. GOLEM-206
