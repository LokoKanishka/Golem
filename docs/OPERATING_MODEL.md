# Operating Model: Golem

## Estado actual

Hoy Golem NO integra todavia a Codex como worker activo dentro del circuito.

El sistema real actual es:

- Diego opera por consola.
- ChatGPT disena arquitectura, orden y bloques.
- OpenClaw ya funciona como sistema vivo.
- El panel del gateway es la consola principal.
- WhatsApp es un canal auxiliar / remoto.
- Codex es una pieza futura prevista, pero no un componente activo del nucleo hoy.

## Principio central

Golem no se disena como si Codex ya estuviera enchufado.

Golem se disena para:
- poder vivir sin Codex;
- poder integrarlo despues sin rehacer el sistema;
- tratar a Codex como worker privilegiado cuando llegue el momento.

## Nucleo actual

### OpenClaw
Cumple el rol de:
- interfaz viva;
- routing;
- sesiones;
- panel de control;
- canal WhatsApp;
- browser relay;
- cuerpo operativo inicial del sistema.

### Panel del gateway
Es la sesion canonica principal de control.

Ahi debe vivir:
- la conversacion principal;
- el seguimiento de tareas;
- el estado operativo serio;
- la trazabilidad humana del sistema.

### WhatsApp
No es la sesion ontologica principal.

Su funcion es:
- control remoto;
- alertas;
- consultas rapidas;
- uso de lujo cuando haga falta;
- canal de entrega secundaria.

### Diego
Es el operador efectivo real del sistema en esta etapa.

### ChatGPT
Cumple el rol de arquitecta conversacional:
- ordena;
- disena;
- propone contratos;
- estructura fases;
- baja decisiones a bloques concretos.

### Codex
Todavia no esta integrado.
Se lo piensa como:
- posible worker futuro;
- herramienta de ejecucion sobre repo;
- componente importante pero no obligatorio en el arranque.

## Decision arquitectonica actual

La decision correcta en esta etapa es:

- conservar vivo lo que ya funciona;
- gobernarlo desde el repo;
- documentar antes de automatizar;
- evitar acoplar el nucleo a una pieza todavia no integrada;
- dejar preparado el sistema para incorporar workers despues.

## Regla de diseno

Golem debe ser:

- panel-first;
- OpenClaw-centered;
- WhatsApp-auxiliary;
- worker-ready;
- repo-governed.

## Implicacion practica

Todavia no corresponde disenar la integracion viva con Codex como si ya existiera.

Antes hay que fijar:

1. modelo operativo;
2. contrato de tareas general;
3. verdad canonica de sesiones;
4. politica de artefactos;
5. limites entre interfaz, ejecucion y estado.

## Horizonte

Mas adelante, si Codex entra de forma real, debera hacerlo como:

- worker de primera clase;
- despertable bajo demanda;
- subordinado al modelo operativo de Golem;
- conectado al sistema sin reemplazar la sesion canonica del panel.

## Formula actual correcta

Hoy la formula correcta es:

- OpenClaw = cuerpo operativo actual
- panel = consola principal
- WhatsApp = remoto auxiliar
- repo = fuente de verdad en construccion
- Codex = worker futuro posible
