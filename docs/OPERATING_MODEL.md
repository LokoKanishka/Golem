# Operating Model: Golem

## Estado actual
Golem todavía no integra a Codex como worker activo.
Hoy el sistema real es:

- Diego opera por consola
- ChatGPT diseña arquitectura, orden y bloques
- OpenClaw ya funciona como sistema vivo
- El panel del gateway es la consola principal
- WhatsApp es canal auxiliar / remoto
- Codex es una pieza futura posible, no componente activo actual

## Principio central
No se diseña Golem como si Codex ya estuviera enchufado.
Se diseña Golem para que pueda integrarlo después sin rehacer el sistema.

## Núcleo actual
- OpenClaw
- panel del gateway
- sesión principal de control
- canal WhatsApp auxiliar
- browser relay por Chrome
- repo Golem como fuente de verdad de la arquitectura

## Núcleo futuro posible
- Codex como worker despertable
- wrappers de tareas
- outbox estructurado por task_id
- callbacks o ACP
- desktop bridge / control de escritorio

## Jerarquía funcional
1. Panel del gateway = superficie principal de operación
2. WhatsApp = lujo operativo, control remoto y alertas
3. OpenClaw = cuerpo operativo / routing / tools / sesión
4. Repo Golem = fuente de verdad
5. Codex = worker futuro de primera clase, no dependencia actual obligatoria

## Regla de diseño
Toda nueva pieza debe poder agregarse sin romper:
- la centralidad del panel
- la condición auxiliar de WhatsApp
- la gobernabilidad desde repo
- la posibilidad de reemplazar o apagar Codex sin matar Golem

## Prohibiciones
- No tratar WhatsApp como chat ontológicamente principal
- No tratar a Codex como si ya fuera núcleo vivo
- No mutar el sistema real sin reflejarlo en el repo
