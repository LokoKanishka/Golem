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
- la descripcion final explicita sus fuentes por claim y no presenta OCR ni layout heuristico como certeza total
- para escritorio, el listado de ventanas del desktop actual no prueba por si solo que todas esten completamente visibles u unobstruidas
- los smokes usan `GOLEM_HOST_CAPABILITIES_ROOT` bajo `mktemp` para aislar corridas de prueba; fuera de smoke, el default sigue siendo `diagnostics/host-capabilities/`

## Que sigue fuera en esta fase

- interpretacion multimodal profunda de iconografia, diagramas o imagenes sin texto
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
