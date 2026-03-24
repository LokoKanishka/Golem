# Host Capabilities

Esta fase abre una primera capa explicita de `host perception + host action` para Golem.

## Que puede ver ahora

- screenshot real del escritorio completo
- screenshot real de la ventana activa
- listado real de ventanas con `window_id`, `pid` y titulo
- contexto visible rapido a partir de las ventanas abiertas
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

## Que sigue fuera en esta fase

- OCR o interpretacion profunda del contenido visual
- control fino de ventanas por workspace/monitor
- navegacion web general fuera de Playwright o carriles ya existentes
- operacion remota de la LAN mas alla de inspeccion basica local

## Verificacion oficial minima

- `./scripts/verify_task_lane_enforcement.sh`
- `./scripts/task_validate.sh --all --strict`
- `./tests/smoke_host_perception_session.sh`
- `./tests/smoke_host_action_lane.sh`
- `./tests/smoke_host_inspection_lane.sh`
