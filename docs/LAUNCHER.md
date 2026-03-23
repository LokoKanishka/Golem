# Golem Launcher

## Que abre

`scripts/launch_golem.sh` prepara una sesion diaria de trabajo de Golem con piezas que ya existen en la maquina:

- entra al repo `~/Escritorio/golem`
- verifica `openclaw-gateway.service` por `systemd --user` y lo arranca si hace falta
- espera unos segundos para darle tiempo al gateway a quedar estable
- levanta el stack local minimo del carril diario:
  - `golem-task-panel-http.service`
  - `golem-whatsapp-bridge.service`
- valida que task API + bridge queden sanos antes de seguir
- resuelve la URL del panel con `openclaw dashboard --no-open`
- abre Google Chrome con dos tabs: el dashboard de OpenClaw y una pagina de trabajo util
- abre VS Code apuntando al repo
- ejecuta `./scripts/self_check.sh`
- imprime un resumen corto con repo, dashboard, tab de trabajo y estado general del self-check

## Que automatiza

El launcher evita tener que levantar cada componente a mano todos los dias. Se apoya en comandos ya disponibles y estables:

- `systemctl --user start openclaw-gateway.service`
- `./scripts/golem_host_stack_ctl.sh start`
- `./scripts/golem_host_stack_ctl.sh healthcheck`
- `openclaw dashboard --no-open`
- `google-chrome`
- `code`
- `./scripts/self_check.sh`

No toca `~/.openclaw`, no cambia configuracion del gateway y no agrega integraciones nuevas.

## Stack Diario

El runner operativo minimo del host ahora vive en:

```text
./scripts/golem_host_stack_ctl.sh
```

Comandos utiles:

```bash
cd ~/Escritorio/golem
./scripts/golem_host_stack_ctl.sh start
./scripts/golem_host_stack_ctl.sh status
./scripts/golem_host_stack_ctl.sh healthcheck
./scripts/golem_host_stack_ctl.sh diagnose
./scripts/golem_host_stack_ctl.sh stop
```

Orden operativo resuelto:

- arranca primero la task API local;
- despues arranca el bridge de WhatsApp apuntando a esa API;
- al apagar, frena primero el bridge y despues la API.

Se eligio resolver la dependencia API -> bridge en este carril operativo y en `self_check`, sin acoplar duro las units entre si. Eso mantiene flexibilidad para servicios alternativos o smokes con nombres temporales.

## Diagnostico profundo

Cuando haga falta evidencia host-level mas profunda, el stack local tiene un runner explicito:

```bash
./scripts/golem_host_diagnose.sh
```

Tambien puede invocarse desde el mismo carril diario:

```bash
./scripts/golem_host_stack_ctl.sh diagnose
```

Y para recuperar rapido el ultimo snapshot util:

```bash
./scripts/golem_host_last_snapshot.sh
```

Cada ejecucion deja un snapshot timestamped en `diagnostics/host/` con:

- `summary.txt`
- `manifest.json`
- status y healthcheck de task API + bridge
- `systemctl --user status/show` de ambos servicios
- tails de `journalctl --user -u ...`
- tabla de procesos relevante
- sockets/puertos relevantes

El runner no intenta corregir el host. En esta fase solo congela evidencia util y persistente para auditoria local rapida.

## Diagnostico automatico por falla

El carril diario ahora dispara snapshot automatico cuando falla alguno de estos puntos:

- `golem_host_stack_ctl.sh start`
- `golem_host_stack_ctl.sh healthcheck`
- `golem_host_stack_ctl.sh restart`
- la espera de startup del stack desde `scripts/launch_golem.sh`
- el `self_check` del launcher cuando `task_api` o `whatsapp_bridge_service` no quedan en `OK`, o cuando el estado general cae en `FAIL`

El snapshot automatico se genera con:

```bash
./scripts/golem_host_diagnose.sh auto --source <source> --reason <reason>
```

Guardas de este tramo:

- cooldown por defecto de 30 segundos para evitar spam de snapshots iguales;
- registro del ultimo disparo en `state/tmp/golem_host_diagnose_auto_state.json`;
- `GOLEM_HOST_DIAG_DISABLE_AUTO=1` para evitar recursion interna durante el propio diagnostico;
- `GOLEM_HOST_AUTO_DIAGNOSE=0` si hace falta inhibir el auto-disparo temporalmente.

Cada snapshot deja visible en `summary.txt` y `manifest.json`:

- `trigger_mode`
- `trigger_source`
- `trigger_reason`
- `trigger_requested_at_utc`

Cuando una falla del stack dispara auto-diagnostico, `golem_host_stack_ctl.sh` y `launch_golem.sh` ahora imprimen un bloque corto y consistente con:

- motivo breve
- servicios afectados
- contexto corto del gateway
- ultima senal breve del gateway si existe
- ruta del snapshot
- `look_first` apuntando a `summary.txt`
- `look_next` apuntando a `manifest.json`
- timestamp
- helper rapido `./scripts/golem_host_last_snapshot.sh`

## Self Check

`./scripts/self_check.sh` ahora informa tambien:

- `task_api`
- `whatsapp_bridge_service`

Con señales de:

- enabled/disabled
- active/inactive
- healthcheck
- URL/base y ultima operacion util cuando corresponde

Para revisar solo el stack local en un smoke o entorno controlado, se pueden omitir las señales externas:

```bash
GOLEM_SELF_CHECK_SKIP_GATEWAY=1 \
GOLEM_SELF_CHECK_SKIP_WHATSAPP=1 \
GOLEM_SELF_CHECK_SKIP_BROWSER=1 \
GOLEM_SELF_CHECK_SKIP_TABS=1 \
./scripts/self_check.sh
```

## Que sigue siendo manual

Hay partes operativas que el launcher no intenta forzar:

- dejar el relay del browser en estado `ON` si la extension necesita confirmacion manual
- autenticaciones o sesiones externas que dependan del operador
- elegir otra pagina de trabajo distinta de la default

Para cambiar la pagina de trabajo sin editar el script, se puede usar:

```bash
GOLEM_WORK_URL="https://es.wikipedia.org/wiki/Wikipedia:Portada" ./scripts/launch_golem.sh
```

Tambien se puede ajustar la espera inicial:

```bash
GOLEM_LAUNCH_WAIT_SECONDS=5 ./scripts/launch_golem.sh
```

Y la espera extra del stack local:

```bash
GOLEM_STACK_WAIT_SECONDS=4 ./scripts/launch_golem.sh
```

## Acceso directo de Ubuntu

`scripts/install_desktop_entry.sh` instala un `.desktop` de usuario en:

```text
~/.local/share/applications/golem.desktop
```

Ese archivo se genera desde `desktop/golem.desktop.template` y apunta al launcher del repo.

Se eligio `Terminal=true` para que el operador vea el `self_check`, el resumen y cualquier warning temprano del arranque. Como el launcher corre comandos operativos, esconder la terminal haria mas dificil detectar problemas de gateway o dependencias faltantes.

## Reinstalar el acceso directo

Para volver a materializar el acceso directo:

```bash
cd ~/Escritorio/golem
./scripts/install_desktop_entry.sh
```

## Ejecutarlo sin el .desktop

Se puede lanzar directo desde terminal:

```bash
cd ~/Escritorio/golem
./scripts/launch_golem.sh
```
