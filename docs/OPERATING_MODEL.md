# Operating Model

Fecha de actualizacion: 2026-03-30

## Formula operativa actual

- Golem = OpenClaw/orquestacion/interfaz
- panel = consola principal
- WhatsApp = canal auxiliar/remoto
- repo = fuente de verdad del estado versionado
- workers externos = capacidad subordinada al carril canonico, no centro del sistema

## Nucleo vigente

El nucleo operativo vigente que hoy queda respaldado por el repo es:

- OpenClaw como cuerpo operativo e interfaz viva
- el panel del gateway como sesion canonica de control
- el carril canonico de tareas en `tasks/`
- una API local unica para leer y mutar ese carril
- una superficie visible minima del panel montada sobre esa misma API
- WhatsApp como canal auxiliar que consulta o muta a traves del bridge local y la misma API

La lectura correcta del sistema hoy es `panel-first` y `OpenClaw-centered`.

## Panel

El panel es la consola principal.

Eso implica:

- la sesion canonica vive ahi
- el seguimiento serio del estado vive ahi
- las tareas canonicas se leen y mutan desde el mismo contrato local
- no corresponde tratar a WhatsApp como sesion principal ni como fuente ontologica del sistema

## WhatsApp

WhatsApp es un canal auxiliar, remoto y de control operativo.

Su lugar vigente es:

- alertas
- consultas rapidas
- mutaciones minimas soportadas por el bridge
- entrega o seguimiento remoto cuando haga falta

No forma parte del nucleo como sesion principal y no debe redefinir el contrato central.

## Criterio actual sobre workers externos

El repo ya documenta handoff, governance y controlled runs de Codex CLI, pero el criterio vigente es conservador:

- un worker externo solo entra por tarea delegada y policy explicita
- el worker no reemplaza la sesion canonica del panel
- el worker no debe mutar por fuera del carril canonico de tareas
- el worker no convierte a Golem en un sistema de colas, callbacks o scheduling
- el cierre semantico sigue siendo explicito y auditable

En otras palabras: los workers externos existen como capacidad complementaria de ejecucion, no como nucleo operativo diario.

## Que no forma parte del nucleo vigente

No deben leerse como parte del estado principal actual:

- bootstrap historico
- documentos de etapas previas usados solo como contexto
- placeholders o scaffolding bajo `openclaw/`
- evidencia local bajo `state/live/`
- runtime-only traces dentro de `handoffs/`
- experimentos o desvíos que abran una segunda arquitectura paralela

Tampoco corresponde presentar como nucleo vigente:

- despliegue remoto
- auth compleja
- una interfaz adicional separada del panel/API actual
- automatizacion completa de workers

## Regla practica

Si algo compite con el contrato panel/API/task lane, no entra en el nucleo vigente sin abrir un tramo aparte.

Mientras tanto, el estado principal del proyecto sigue siendo:

- panel como centro
- WhatsApp como auxiliar
- repo como fuente de verdad versionada
- workers externos como capacidad opcional y subordinada
