# V1.5 Tasks: Golem

## Objetivo
Definir una etapa intermedia entre V1 y una futura integración con workers o desktop agency ampliada.

## Principio
V1.5 sigue sin depender de un worker externo.
Todo lo que entra acá debe poder resolverse con OpenClaw y su superficie actual, o con extensiones muy cercanas a lo ya probado.

---

## Tareas candidatas de V1.5

### 1. Navegación ampliada
- abrir una URL pedida por el usuario
- cambiar entre pestañas abiertas
- identificar cuál es la pestaña activa
- listar pestañas útiles para una tarea

### 2. Lectura más precisa
- buscar una palabra o expresión dentro de la página
- extraer un bloque puntual
- identificar secciones o apartados relevantes
- comparar dos páginas abiertas de forma simple

### 3. Producción simple de artefactos
- guardar un resumen en archivo de texto o markdown
- dejar el archivo en una carpeta conocida
- devolver al usuario el nombre o la ruta del artefacto

### 4. Observación ampliada del sistema
- self-check del gateway
- self-check de WhatsApp
- self-check del browser relay
- diagnóstico breve de “qué está andando y qué no”

### 5. Entrega más ordenada
- responder con formato más estable
- distinguir entre respuesta breve, resumen y reporte
- preparar una salida lista para revisión humana

---

## Qué sigue fuera de V1.5

- worker externo vivo
- delegación real a Codex
- pipeline completo con task_id funcional
- desktop agency completa
- control GUI general del host
- vigilancia persistente compleja
- autonomía prolongada

---

## Regla de inclusión en V1.5
Una tarea entra en V1.5 si:
1. no requiere un worker externo;
2. no exige mutaciones delicadas del host;
3. extiende de forma natural lo ya probado en V1;
4. agrega valor operativo real al panel y al canal auxiliar.

## Regla de exclusión
Una tarea queda fuera de V1.5 si:
- depende de ejecución larga estructurada;
- necesita artefactos complejos;
- exige control completo del escritorio;
- o introduce demasiada complejidad de coordinación.
