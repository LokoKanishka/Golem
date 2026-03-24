# Host Capabilities

Este directorio guarda corridas persistidas del carril general del host.

Entry points:

- `./scripts/golem_host_perceive.sh`: evidencia real de escritorio/sesion grafica
- `./scripts/golem_host_describe.sh`: descripcion semantica auditada apoyada en metadata + screenshot + OCR aproximado
- `./scripts/golem_host_act.sh`: acciones auditables sobre la sesion o el host
- `./scripts/golem_host_inspect.sh`: inspeccion real de procesos, servicios y puertos

Que persiste cada corrida:

- `summary.txt`: lectura humana rapida
- `manifest.json`: estructura completa del run
- artefactos puntuales segun el carril:
  - screenshots y ventanas para percepcion
  - screenshot objetivo, OCR crudo, OCR mejorado, OCR normalizado, layout, `surface-profile.json`, `structured-fields.json` con campos generales, finos y refinamientos contextuales, descripcion y fuentes para vision semantica
  - stdout/stderr o cambios de foco para accion
  - procesos, servicios y puertos para inspeccion

Estas corridas requieren una sesion real del host para la parte grafica:

- `DISPLAY` valido
- `XDG_SESSION_TYPE` compatible
- herramientas del host como `wmctrl`, `xdotool` y el helper de screenshot

Persistencia:

- por default, los entry points escriben bajo este directorio del repo (`diagnostics/host-capabilities/`)
- los smokes oficiales pueden redirigir `GOLEM_HOST_CAPABILITIES_ROOT` a un `mktemp` para aislamiento, sin cambiar el contrato de artefactos ni las rutas relativas dentro de cada run

Limitaciones deliberadas de esta fase:

- la vision semantica usa OCR aproximado y reglas honestas; no hace interpretacion multimodal profunda
- el layout se infiere por heuristicas simples sobre texto visible; no reemplaza una segmentacion visual fuerte
- la clasificacion de superficie (`editor`, `chat`, `terminal`, `browser-web-app`, `unknown`) es aproximada y se apoya en metadata + OCR + layout
- la priorizacion de `useful_lines` y `useful_regions` busca utilidad operativa por tipo de superficie, no una verdad total sobre la UI
- los `structured_fields`, sus `fine_fields` y los `contextual_refinements` se extraen desde metadata + OCR + heuristicas y pueden quedar vacios o parciales cuando el frame no ofrece suficiente señal
- no controla multiples monitores de forma especializada
- no automatiza navegadores complejos fuera de los carriles ya existentes
- no abre autonomia opaca: cada accion queda materializada como evidencia local
