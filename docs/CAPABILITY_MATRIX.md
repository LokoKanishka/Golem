# Capability Matrix

Fecha de auditoria: 2026-03-31

## 1. Resumen ejecutivo

Esta auditoria separa realidad operativa de promesa.

- `PASS`: gateway local, panel web/control UI servida, WhatsApp conectado, inventario de profiles/browser plugin, percepcion y descripcion semantica del host.
- `PARTIAL`: salud general del host OpenClaw, consistencia entre `openclaw status` y `openclaw channels status --probe`, modelo panel-first/routing, Chrome real visible pero no adjuntable.
- `BLOCKED`: browser nativo usable, attach `user`, lectura real de pagina, artifacts browser, helper CDP vivo en este momento, worker externo listo para operar de verdad, control host total.
- `UNVERIFIED`: delivery basico real por WhatsApp en este tramo, accion host mutante general.
- `OUT-OF-SCOPE`: instalar o inyectar plugins nuevos en el host vivo.

Lectura corta: OpenClaw hoy esta sano como gateway/control plane local con WhatsApp conectado. La brecha fuerte sigue estando en browser real y en todo lo que depende de ese browser o del stack local task API/bridge para subir a una operacion mas completa.

## 2. Estado del host y version

- Repo auditado: `~/Escritorio/golem`
- Rama auditada: `main`
- Estado git al iniciar: limpio
- OpenClaw: `2026.3.28 (f9b1079)`
- Gateway: `ws://127.0.0.1:18789`
- Dashboard: `http://127.0.0.1:18789/`
- Browser profile por defecto en config: `user`
- `userDataDir` del profile `user`: `/home/lucy-ubuntu/.antigravity-lucy/home/.gemini/antigravity-browser-profile`

Baseline usado como evidencia en este tramo:

- `git status --short`
- `git branch --show-current`
- `git log --oneline -8`
- `find docs handoffs scripts tests -maxdepth 2 | sort | sed -n '1,260p'`
- `openclaw --version`
- `openclaw gateway status`
- `openclaw status || true`
- `openclaw channels status --probe || openclaw channels status`
- `openclaw doctor || true`
- `openclaw plugins list`
- `openclaw browser profiles || true`
- `openclaw browser status || true`
- `./scripts/browser_cdp_tool.sh tabs || true`

## 3. Matriz por capability

| Capability | Estado | Evidencia | Que significa hoy | Riesgo / nota |
| --- | --- | --- | --- | --- |
| Gateway health | `PASS` | `openclaw gateway status` -> `Runtime: running`, `RPC probe: ok` | El gateway local esta vivo y responde de forma verificable. | Hay otras unidades gateway-like detectadas; no bloquean este estado, pero agregan complejidad operacional. |
| Panel web operativo | `PASS` | `curl -I http://127.0.0.1:18789/` -> `HTTP/1.1 200 OK` | La UI HTTP del gateway responde en loopback. | No prueba workflows internos del panel; prueba que la superficie esta servida. |
| Control UI viva | `PASS` | `curl http://127.0.0.1:18789/` contiene `<title>OpenClaw Control</title>` | La control UI no es solo puerto abierto; esta sirviendo la app correcta. | Sigue siendo una prueba de reachability, no de interaccion semantica. |
| Health general | `PARTIAL` | `openclaw status` muestra gateway y WhatsApp OK; `openclaw doctor` advierte migracion omitida y servicios gateway-like extra | OpenClaw base esta arriba, pero no corresponde vender el host como totalmente sano. | Verifies de browser y worker exponen huecos operativos reales. |
| WhatsApp conectado | `PASS` | `openclaw status` -> `WhatsApp ON OK`; `openclaw channels status --probe` -> `linked, running, connected` | El canal WhatsApp esta conectado hoy. | Esto no equivale a probar envio real en este tramo. |
| Delivery basico por WhatsApp | `UNVERIFIED` | No se ejecuto send real en este tramo para evitar side effects | No hay evidencia nueva de entrega real durante esta auditoria. | La instalacion puede venir sana de antes, pero aqui no se reclamo sin prueba nueva. |
| Consistencia `status` vs `channels status --probe` | `PARTIAL` | Ambos muestran WhatsApp conectado; difieren en el detalle visible (`linked +549...` vs `allow:+156...`) | Coinciden en salud/conectividad, pero no dan una misma vista textual del estado. | Conviene no asumir equivalencia semantica total entre ambas salidas. |
| Sesion principal en panel | `PARTIAL` | `docs/OPERATING_MODEL.md` define panel-first; `openclaw status` muestra sesion `agent:main:main` | El modelo operativo vigente sigue siendo panel-first. | En este tramo no se navego la UI para demostrar uso humano efectivo del panel como sesion canonica. |
| WhatsApp como canal auxiliar | `PASS` | `README.md`, `docs/OPERATING_MODEL.md` y `~/.openclaw/openclaw.json` alinean WhatsApp como canal, no como sesion principal | El modelo documentado y la config runtime son coherentes en este punto. | Sigue faltando un send real en este tramo. |
| Routing vivo vs modelo documentado | `PARTIAL` | `~/.openclaw/openclaw.json` enlaza WhatsApp default a `wschat`; `openclaw status` muestra sesiones `main` y sesiones WhatsApp separadas | No hay evidencia de que WhatsApp haya tomado el lugar del panel; el modelo parece respetado. | No hubo trace e2e de mensaje inbound/outbound durante esta auditoria. |
| Browser plugin bundled | `PASS` | `openclaw plugins list` -> `Browser ... loaded` | El plugin browser stock esta cargado. | Plugin cargado no equivale a browser utilizable. |
| Browser profiles inventory | `PASS` | `openclaw browser profiles` -> `user [existing-session]` y `openclaw` | OpenClaw reconoce los carriles browser esperados. | El inventario existe aunque la operacion este bloqueada. |
| Browser `user` attachable | `BLOCKED` | `openclaw browser --browser-profile user snapshot` -> timeout esperando tabs; `ECONNREFUSED 127.0.0.1:9222` | El attach `existing-session` no esta usable hoy. | Esta es la deuda operativa principal del browser nativo. |
| Browser CLI usable | `BLOCKED` | `openclaw browser --browser-profile user status/tabs` fallan; `verify_browser_stack.sh --diagnosis-only` clasifica `navigation/reading/artifacts` como `BLOCKED` | La CLI browser de OpenClaw no es una superficie diaria confiable en este host. | No confundir profile configurado con operator lane usable. |
| Browser managed `openclaw` usable | `BLOCKED` | `openclaw browser --browser-profile openclaw tabs` -> `No tabs`; snapshot falla con `Missing X server or $DISPLAY` | El carril managed tampoco resuelve el problema hoy. | Ni attach existing-session ni fallback managed estan cerrando la brecha. |
| Browser CDP helper versionado | `PASS` | Existen `scripts/browser_cdp_tool.sh` y `scripts/browser_cdp_tool.js`; el helper soporta `tabs/open/snapshot/find` | El repo ya tiene un carril paralelo definido y versionado. | La existencia del helper no garantiza un endpoint vivo. |
| Browser CDP helper usable en vivo | `BLOCKED` | `./scripts/browser_cdp_tool.sh tabs` -> `ERROR: fetch failed`; con `GOLEM_BROWSER_DEVTOOLS_FILE=.../DevToolsActivePort` sigue fallando; `curl 127.0.0.1:9222/json/list` falla | El helper no puede leer Chrome real en el estado actual del host. | El `DevToolsActivePort` existe pero hoy apunta a un puerto sin listener util. |
| Chrome real visible | `PARTIAL` | `ps -ef` muestra procesos Chrome; existe `DevToolsActivePort`; `ss -ltnp` no muestra listener en `9222` | Chrome vive como proceso, pero no como endpoint CDP utilizable para esta auditoria. | "Chrome abierto" no equivale a "OpenClaw o helper lo pueden usar". |
| Lectura de una pagina real | `BLOCKED` | `verify_browser_stack.sh --diagnosis-only` deja `navigation/reading/artifacts` en `BLOCKED` | Hoy no se puede reclamar lectura browser real por OC puro ni por helper paralelo. | Esta ausencia debe tratarse como bloqueo real, no como detalle menor. |
| Worker governance/documentation | `PASS` | `docs/WORKER_RUN_GOVERNANCE.md`, `docs/CODEX_CONTROLLED_RUN.md`, scripts `task_worker_*` y `verify_worker_orchestration_stack.sh` | La capa de governance y controlled run existe de verdad en el repo. | Documentacion y scripts listos no implican readiness host. |
| Worker externo real / orchestration readiness | `BLOCKED` | `./scripts/verify_worker_orchestration_stack.sh` falla en las 3 subcapabilities; el self-check previo marca `browser_relay FAIL`, `task_api FAIL`, `whatsapp_bridge_service FAIL`; el chain audit detecta drift | El carril worker no esta listo para venderse como capacidad operativa estable hoy en este host. | Hay diseño y tooling, pero el estado vivo no acompaña. |
| Host perception read-side | `PASS` | `./scripts/golem_host_perceive.sh json` genera screenshots, lista ventanas y detecta active window | El repo ya puede percibir el desktop local de forma verificable. | Esto es read-side; no es control total del host. |
| Host semantic description read-side | `PASS` | `./scripts/golem_host_describe.sh active-window --json` genera `surface_state_bundle` y clasificacion de la ventana activa | Hay descripcion semantica real del desktop en esta maquina. | Es aproximada/OCR-based; no es estado interno perfecto ni control. |
| Desktop control general | `UNVERIFIED` | Existen `golem_host_act.sh focus/type/key/open`, pero no se ejercieron para no mutar el desktop vivo sin necesidad | La capa de accion existe como superficie repo-local. | No corresponde inflar esto a capacidad probada en este tramo. |
| Control host total | `BLOCKED` | No hay evidencia de control host end-to-end; browser real esta bloqueado y la accion host no se probo de forma operativa integral | Hoy no existe base honesta para prometer control total del host. | Este es precisamente uno de los relatos a evitar. |
| Ecosistema bundled visible | `PASS` | `openclaw plugins list` muestra `browser` y `whatsapp` cargados; `slack`, `telegram`, `discord`, `signal`, `brave` existen pero deshabilitados | El ecosistema stock existe y es visible en la instalacion. | Existencia de categorias no equivale a host listo para usarlo todo. |
| Ecosistema/plugin injection en host vivo | `OUT-OF-SCOPE` | Este tramo no instala nada nuevo por regla; `openclaw status` reporta `Plugin compatibility: none` | No se audito ni se intento extender el host con plugins nuevos. | No conviene usar este tramo para sacar conclusiones infladas sobre "ecosistema listo". |

## 4. Nucleo OC real en esta maquina

Lo que hoy si merece el nombre de nucleo OpenClaw operativo en este host:

- gateway local con systemd, proceso vivo y `RPC probe: ok`
- panel/control UI HTTP local sirviendo correctamente
- inventario de agentes/sesiones accesible por `openclaw status`
- canal WhatsApp conectado y reconocido por `status` y `channels status --probe`
- plugin browser stock cargado y perfiles browser inventariables

Lo que no debe venderse como nucleo operativo ya resuelto:

- browser diario usable desde `openclaw browser ...`
- lectura browser real
- artifacts browser
- worker externo listo para operar como carril estable
- control host total

## 5. Carriles paralelos aceptados

Carriles paralelos aceptados, con limites explicitados:

- `scripts/browser_cdp_tool.sh`
  - aceptado solo como sidecar pragmatico para cuando exista un endpoint CDP real y verificable
  - no reemplaza la verdad del browser nativo de OpenClaw
  - hoy esta bloqueado en este host por falta de listener util
- `scripts/golem_host_perceive.sh`
  - aceptado como percepcion read-side del desktop
  - sirve para pruebas de evidencia host, no para afirmar control total
- `scripts/golem_host_describe.sh`
  - aceptado como descripcion semantica read-side del host
  - su salida es heuristica/OCR, no estado oculto garantizado
- governance/controlled-run de workers en el repo
  - aceptado como carril subordinado y auditable
  - no es el centro operativo del sistema y hoy no esta listo para venderse como capacidad estable del host

## 6. Capacidades bloqueadas o inmaduras

- `openclaw browser --browser-profile user` no logra attach usable; cae en timeout/`ECONNREFUSED`.
- El carril managed `openclaw` tampoco entrega tabs ni snapshot util.
- El helper CDP existe pero hoy no puede leer un endpoint vivo; el `DevToolsActivePort` apunta a `9222` sin listener util.
- Los verifies canonicos de worker/orchestration fallan en este host porque el self-check detecta browser relay caido y task API/bridge local inactivos.
- El execution audit de chain tambien muestra drift cuando la root cae terminal demasiado temprano.
- Delivery WhatsApp real no se reclamo en este tramo porque no se ejecuto un send vivo nuevo.

## 7. Frentes que NO conviene atacar ahora

- Instalar plugins comunitarios nuevos para "ver si eso arregla algo".
- Abrir nuevas features browser sin cerrar antes la verdad del attach real.
- Vender escritorio completo o control host total.
- Escalar automation de workers mientras la readiness local siga fallando.
- Mezclar esta auditoria con docencia, APD o nuevos frentes de producto.

## 8. Proximo tramo unico recomendado

Resolver la verdad del browser en este host, y solo eso.

Objetivo del proximo tramo:

- dejar en `PASS` un unico camino reproducible para obtener tabs + lectura real de pagina
- o degradar formalmente el browser nativo a deuda conocida y cerrar un sidecar CDP realmente verificable con smoke corto y automatico

Lo que no conviene hacer antes de eso:

- reabrir workers
- prometer control host total
- abrir ecosistema/plugin expansion
- agregar features nuevas sobre una base browser todavia ambigua
