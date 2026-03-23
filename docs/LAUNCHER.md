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
./scripts/golem_host_stack_ctl.sh stop
```

Orden operativo resuelto:

- arranca primero la task API local;
- despues arranca el bridge de WhatsApp apuntando a esa API;
- al apagar, frena primero el bridge y despues la API.

Se eligio resolver la dependencia API -> bridge en este carril operativo y en `self_check`, sin acoplar duro las units entre si. Eso mantiene flexibilidad para servicios alternativos o smokes con nombres temporales.

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
