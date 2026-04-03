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
- extraccion auditada de `structured_fields` segun el tipo de superficie, con campos generales, `fine_fields` y `contextual_refinements` para distinguir mejor lo activo, lo visible y lo secundario, siempre con `value`, `confidence` y `source_refs`
- consolidacion auditada en `surface_state_bundle` para resumir el estado operativo visible por superficie sin esconder incertidumbre
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
- los `structured_fields` se apoyan en metadata, OCR normalizado, `useful_lines`, `useful_regions` y surface classification; ahora incluyen `fine_fields` por superficie y `contextual_refinements` para distinguir activo/primario/secundario/historico, y dejan huecos cuando la señal visible no alcanza
- el `surface_state_bundle` consolida esas capas en un estado operativo mas utilizable por superficie, pero sigue siendo una heuristica auditada y puede quedar parcial cuando el OCR o el layout no alcanzan
- la descripcion final explicita sus fuentes por claim y no presenta OCR, layout ni surface classification heuristica como certeza total
- para escritorio, el listado de ventanas del desktop actual no prueba por si solo que todas esten completamente visibles u unobstruidas
- los smokes usan `GOLEM_HOST_CAPABILITIES_ROOT` bajo `mktemp` para aislar corridas de prueba; fuera de smoke, el default sigue siendo `diagnostics/host-capabilities/`

## Tipos de superficie y foco de lectura

- `editor / IDE`: prioriza file/tab title, explorer/sidebar, lineas de codigo y errores o trazas visibles
- `chat / messaging workspace`: prioriza contexto de conversacion, mensajes visibles, sidebar de chats y composer/input
- `terminal / console`: prioriza prompt, comando reciente, bloque de salida visible y errores recientes
- `browser / web app`: prioriza header, navegacion, contenido central y CTA o controles textuales
- `unknown / mixed`: conserva lectura honesta cuando la evidencia no alcanza o la pantalla mezcla varios patrones

## Campos estructurados por superficie

- `editor / IDE`: intenta `workspace_or_project`, `file_or_tab_candidates`, `error_candidates`, `active_editor_text_snippets` y `sidebar_context`
- `chat / messaging workspace`: intenta `conversation_title_candidates`, `visible_message_snippets`, `input_area_text` y `sidebar_chat_candidates`
- `terminal / console`: intenta `prompt_candidates`, `command_candidates`, `error_output_candidates` y `recent_output_snippets`
- `browser / web app`: intenta `page_title_candidates`, `header_text`, `sidebar_navigation_candidates`, `primary_content_snippets` y `cta_or_action_text_candidates`
- todos estos campos son aproximados y dependen fuerte de la calidad del OCR y del layout visible

## Subcampos finos por superficie

- `editor / IDE`: intenta `active_file_candidate`, `visible_tab_candidates`, `primary_error_candidate`, `workspace_or_project_candidate` y `explorer_context_candidates`
- `chat / messaging workspace`: intenta `conversation_title_candidate`, `visible_message_snippets`, `input_box_candidate` y `sidebar_conversation_candidates`
- `terminal / console`: intenta `active_prompt_candidate`, `recent_command_candidate`, `primary_error_output_candidate` y `recent_output_block_snippets`
- `browser / web app`: intenta `primary_header_candidate`, `sidebar_navigation_candidates`, `primary_cta_candidate`, `main_content_snippets` y `page_title_candidate`
- los subcampos finos reusan la misma trazabilidad auditable; los nombres singulares devuelven el mejor candidato disponible y los plurales mantienen varias opciones visibles

## Refinamientos contextuales por superficie

- `editor / IDE`: intenta `active_tab_candidate`, `visible_tab_candidates`, `primary_error_candidate`, `secondary_error_candidates`, `active_file_candidate` y `sidebar_context_candidates`
- `chat / messaging workspace`: intenta `active_conversation_candidate`, `sidebar_conversation_candidates`, `input_box_candidate`, `visible_message_snippets` y `composer_text_candidate`
- `terminal / console`: intenta `active_prompt_candidate`, `historical_prompt_candidates`, `recent_command_candidate`, `primary_error_output_candidate` y `recent_output_block_snippets`
- `browser / web app`: intenta `primary_header_candidate`, `primary_cta_candidate`, `secondary_action_candidates`, `sidebar_navigation_candidates` y `main_content_snippets`
- cada refinamiento contextual agrega propiedades simples como `role`, `priority` y `activity_state` para distinguir activo/visible/secundario/historico sin esconder que sigue siendo heuristico
- esta capa depende fuerte de OCR, layout y posicion relativa; si la señal no alcanza, el refinamiento puede quedar vacio u omitido

## Surface State Bundles

- `editor / IDE`: consolida `active_file`, `active_tab`, `visible_tabs`, `primary_error`, `workspace_or_project`, `sidebar_context` y `main_text_focus`
- `chat / messaging workspace`: consolida `active_conversation`, `visible_messages`, `composer_text`, `input_box`, `sidebar_conversations` y `main_text_focus`
- `terminal / console`: consolida `active_prompt`, `recent_command`, `primary_error_output`, `recent_output_block` y `main_text_focus`
- `browser / web app`: consolida `primary_header`, `sidebar_navigation`, `primary_cta`, `main_content`, `page_title` y `main_text_focus`
- cada entrada del bundle mantiene `value`, `confidence`, `source_refs` y, cuando aplica, `derived_from`, `bundle_role` y `surface_type`
- el bundle no inventa estructura nueva: consolida `structured_fields`, `fine_fields` y `contextual_refinements` para que la capa superior tenga un estado visible mas usable
- estos bundles dependen fuerte del OCR y del layout; pueden quedar incompletos, aproximados o vacios cuando la senal no alcanza

## Artefactos nuevos en vision semantica

- `surface-profile.json`: clasificacion de superficie, scores por categoria, evidencia, `useful_lines` y `useful_regions`
- `structured-fields.json`: campos estructurados por tipo de superficie con `value`, `confidence`, `source_refs`, `fine_fields` mas especificos y `contextual_refinements`
- `surface-state.json`: bundle operativo por superficie con campos consolidados, `derived_from` y trazabilidad a fuentes
- `description.json`: ahora incluye `surface_classification`, `useful_lines`, `useful_regions`, `structured_fields` y `surface_state_bundle`
- `summary.txt`: resume categoria detectada, confianza, lineas priorizadas, regiones utiles, campos estructurados generales, subcampos finos, refinamientos contextuales y el bundle operativo consolidado

## Que sigue fuera en esta fase

- interpretacion multimodal profunda de iconografia, diagramas o imagenes sin texto
- accion rica sobre apps a partir de la lectura visual
- control fino de ventanas por workspace/monitor
- navegacion web general fuera de Playwright o carriles ya existentes
- operacion remota de la LAN mas alla de inspeccion basica local

## Verificacion oficial minima

- `./scripts/verify_host_lane_enforcement.sh`
- `./scripts/verify_task_lane_enforcement.sh`
- `./scripts/task_validate.sh --all --strict`
- `./tests/smoke_host_perception_session.sh`
- `./tests/smoke_host_action_lane.sh`
- `./tests/smoke_host_inspection_lane.sh`
- `./tests/smoke_host_describe_lane.sh`
- `./tests/smoke_host_describe_visual_reading.sh`
- `./tests/smoke_host_describe_surface_profiles.sh`
