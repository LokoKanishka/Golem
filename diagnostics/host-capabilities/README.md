# Host Capabilities

Este directorio guarda corridas persistidas del carril general del host.

Entry points:

- `./scripts/golem_host_perceive.sh`: evidencia real de escritorio/sesion grafica
- `./scripts/golem_host_act.sh`: acciones auditables sobre la sesion o el host
- `./scripts/golem_host_inspect.sh`: inspeccion real de procesos, servicios y puertos

Que persiste cada corrida:

- `summary.txt`: lectura humana rapida
- `manifest.json`: estructura completa del run
- artefactos puntuales segun el carril:
  - screenshots y ventanas para percepcion
  - stdout/stderr o cambios de foco para accion
  - procesos, servicios y puertos para inspeccion

Estas corridas requieren una sesion real del host para la parte grafica:

- `DISPLAY` valido
- `XDG_SESSION_TYPE` compatible
- herramientas del host como `wmctrl`, `xdotool` y el helper de screenshot

Limitaciones deliberadas de esta primera fase:

- no hace OCR ni vision semantica avanzada del escritorio
- no controla multiples monitores de forma especializada
- no automatiza navegadores complejos fuera de los carriles ya existentes
- no abre autonomia opaca: cada accion queda materializada como evidencia local
