# Host Capabilities

Esta fase abre una capa explicita de `host perception + host action` y ahora suma un carril auditado de vision semantica del escritorio para Golem.

## Que puede ver ahora

- screenshot real del escritorio completo
- screenshot real de la ventana activa
- listado real de ventanas con `window_id`, `pid` y titulo
- contexto visible rapido a partir de las ventanas abiertas
- descripcion semantica auditada del escritorio, ventana activa o una ventana puntual
- OCR aproximado con evidencia persistida y limites explicitados
- OCR mejorado y texto normalizado para aumentar legibilidad sin borrar el OCR crudo
- layout heuristico de bajo nivel para identificar header, sidebar, main content, footer o paneles equivalentes
- surface classification heuristica para distinguir `editor / IDE`, `chat / messaging workspace`, `terminal / console`, `browser / web app` o `unknown / mixed`
- ranking auditado de `useful_lines` y `useful_regions` segun el tipo de superficie visible
- procesos, servicios de usuario y puertos escuchando en el host

## Que puede operar ahora

- ejecutar comandos del host con stdout/stderr persistidos
- abrir una superficie grafica o app con evidencia del pid
- esperar una ventana por titulo
- hacer focus real sobre una ventana existente
- enviar texto o teclas a la ventana activa

## Entry points

Percepcion:

- `./scripts/golem_host_perceive.sh`
- `./scripts/golem_host_perceive.sh json`
- `./scripts/golem_host_perceive.sh path`

Vision semantica:

- `./scripts/golem_host_describe.sh`
- `./scripts/golem_host_describe.sh desktop`
- `./scripts/golem_host_describe.sh active-window`
- `./scripts/golem_host_describe.sh window --title "Mi ventana"`
- `./scripts/golem_host_describe.sh window --window-id 0x01200007`
- `./scripts/golem_host_describe.sh json`
- `./scripts/golem_host_describe.sh path`

Accion:

- `./scripts/golem_host_act.sh command --label date-check -- date -u`
- `./scripts/golem_host_act.sh open --label dialog -- zenity --entry --title "Golem host action"`
- `./scripts/golem_host_act.sh wait-window --title "Golem host action"`
- `./scripts/golem_host_act.sh focus --title "Golem host action"`
- `./scripts/golem_host_act.sh type --text "hola desde Golem" --window-id 0x01200007`
- `./scripts/golem_host_act.sh key --key Return --window-id 0x01200007`

Inspeccion:

- `./scripts/golem_host_inspect.sh`
- `./scripts/golem_host_inspect.sh json`
- `./scripts/golem_host_inspect.sh path`

## Precision y limites del nuevo carril

- la identidad de ventanas/apps sale de metadata real (`wmctrl`, `xprop`, `ps`)
- el contenido visible sale de screenshots reales
- el texto visible recuperado por OCR se persiste en tres capas auditables: crudo, mejorado y normalizado
- la estructura visible sale de heuristicas simples sobre bounding boxes OCR; sirve para leer mejor layout, no para segmentacion perfecta
- la clasificacion de superficie combina metadata, OCR normalizado y layout heuristico; expone `confidence` (`strong`, `reasonable`, `uncertain`) y no se vende como certeza total
- la descripcion final explicita sus fuentes por claim y no presenta OCR, layout ni surface classification heuristica como certeza total
- para escritorio, el listado de ventanas del desktop actual no prueba por si solo que todas esten completamente visibles u unobstruidas
- los smokes usan `GOLEM_HOST_CAPABILITIES_ROOT` bajo `mktemp` para aislar corridas de prueba; fuera de smoke, el default sigue siendo `diagnostics/host-capabilities/`

## Tipos de superficie y foco de lectura

- `editor / IDE`: prioriza file/tab title, explorer/sidebar, lineas de codigo y errores o trazas visibles
- `chat / messaging workspace`: prioriza contexto de conversacion, mensajes visibles, sidebar de chats y composer/input
- `terminal / console`: prioriza prompt, comando reciente, bloque de salida visible y errores recientes
- `browser / web app`: prioriza header, navegacion, contenido central y CTA o controles textuales
- `unknown / mixed`: conserva lectura honesta cuando la evidencia no alcanza o la pantalla mezcla varios patrones

## Artefactos nuevos en vision semantica

- `surface-profile.json`: clasificacion de superficie, scores por categoria, evidencia, `useful_lines` y `useful_regions`
- `description.json`: ahora incluye `surface_classification`, `useful_lines` y `useful_regions`
- `summary.txt`: resume categoria detectada, confianza, lineas priorizadas y regiones utiles

## Que sigue fuera en esta fase

- interpretacion multimodal profunda de iconografia, diagramas o imagenes sin texto
- accion rica sobre apps a partir de la lectura visual
- control fino de ventanas por workspace/monitor
- navegacion web general fuera de Playwright o carriles ya existentes
- operacion remota de la LAN mas alla de inspeccion basica local

## Verificacion oficial minima

- `./scripts/verify_task_lane_enforcement.sh`
- `./scripts/task_validate.sh --all --strict`
- `./tests/smoke_host_perception_session.sh`
- `./tests/smoke_host_action_lane.sh`
- `./tests/smoke_host_inspection_lane.sh`
- `./tests/smoke_host_describe_lane.sh`
- `./tests/smoke_host_describe_visual_reading.sh`
- `./tests/smoke_host_describe_surface_profiles.sh`
