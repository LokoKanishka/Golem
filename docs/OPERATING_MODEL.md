# Operating Model: Golem

## Purpose

Define the operational model for the current stage of Golem without pretending that Codex is already integrated.

This document is doctrinal, not a claim of live runtime integration.

## Estado actual real

Hoy el flujo real es este:

- Diego opera por consola.
- ChatGPT ayuda con arquitectura, orden y criterio.
- OpenClaw ya existe y funciona como sistema vivo.
- el panel del gateway es la superficie principal de control
- WhatsApp existe como canal auxiliar, remoto y de lujo
- Codex es un worker futuro posible, pero no componente activo del sistema actual

El repo `golem` no despliega hoy el sistema vivo.
El repo documenta, ordena y prepara el modelo para que el sistema pueda crecer sin rehacerse.

## Nucleo actual

El nucleo real de esta etapa es:

- OpenClaw como golem, cuerpo operativo y orquestador
- panel del gateway como sesion canonica y superficie principal
- consola local como forma principal de operacion
- WhatsApp como canal secundario y remoto
- browser relay y demas capacidades vivas ya existentes en OpenClaw
- este repo como fuente doctrinal de arquitectura, contratos y limites

## Nucleo futuro posible

El nucleo futuro posible, todavia no integrado de verdad, podria agregar:

- Codex como worker despertable para trabajo de repo, codigo o documentos
- contratos de tarea mas formales entre panel, repo y worker
- outbox estructurado por `task_id`
- notificaciones y callbacks mas claros
- puentes adicionales de escritorio o ACP si despues hacen falta

La regla es que ese futuro debe enchufarse sobre el nucleo actual.
No al reves.

## Jerarquia operativa

La jerarquia de esta etapa es:

1. panel del gateway = superficie principal y sesion canonica
2. OpenClaw = golem/orquestador/cuerpo operativo
3. consola local = modo principal de operacion humana
4. WhatsApp = canal secundario, remoto y de lujo
5. repo Golem = fuente doctrinal y contractual
6. Codex = worker futuro integrable, no dependencia viva actual

## Panel First

Golem se diseña con criterio `panel first`.

Eso implica:

- la sesion principal vive en el panel del gateway
- el contexto canonico debe poder leerse desde esa superficie
- los resultados importantes deben poder volver a esa superficie
- WhatsApp no debe volverse la verdad principal del sistema

## WhatsApp como auxiliar

WhatsApp en esta etapa significa:

- control remoto
- notificaciones
- canal auxiliar cuando no se esta en la consola principal

No significa:

- chat ontologicamente principal
- sesion canonica
- lugar exclusivo donde viva el estado real de una tarea

## OpenClaw como golem operativo

En esta etapa OpenClaw ya cumple el rol de:

- cuerpo operativo
- capa de herramientas
- orquestacion viva
- punto real de contacto con el sistema actual

Por eso el repo debe describir a OpenClaw como nucleo vivo actual, no como una promesa futura.

## Codex como futuro integrable

Codex se considera:

- worker futuro posible
- buen candidato para trabajo despertable y acotado
- pieza que debe poder sumarse despues

Codex no se considera hoy:

- componente activo actual
- verdad operacional del sistema
- dependencia obligatoria para que Golem exista

## Regla de diseno

Toda pieza nueva debe cumplir estas condiciones:

- no romper la centralidad del panel
- no convertir WhatsApp en la superficie principal
- no asumir que Codex ya esta integrado
- permitir una integracion futura de Codex sin rehacer el modelo
- permitir apagar o reemplazar a Codex sin matar el sistema

## Prohibiciones de esta etapa

En esta etapa no corresponde:

- tocar `~/.openclaw`
- cambiar `systemd`
- mutar gateway, channels o browser relay vivos
- describir a Codex como worker ya conectado
- diseñar como si WhatsApp fuera la sesion principal
- mover la verdad operacional fuera del panel del gateway
- vender como integrada una capa que hoy solo es contractual o doctrinal

## Regla de verdad

La verdad de esta etapa se ordena asi:

1. el sistema vivo actual corre en OpenClaw
2. el panel del gateway es la sesion/superficie principal
3. este repo documenta el modelo operativo y prepara el futuro
4. WhatsApp refleja o auxilia, pero no manda
5. Codex se diseña como integrable despues, no como realidad presente
