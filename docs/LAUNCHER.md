# Golem Launcher

## Que abre

`scripts/launch_golem.sh` prepara una sesion diaria de trabajo de Golem con piezas que ya existen en la maquina:

- entra al repo `~/Escritorio/golem`
- verifica `openclaw-gateway.service` por `systemd --user` y lo arranca si hace falta
- espera unos segundos para darle tiempo al gateway a quedar estable
- resuelve la URL del panel con `openclaw dashboard --no-open`
- abre Google Chrome con dos tabs: el dashboard de OpenClaw y una pagina de trabajo util
- abre VS Code apuntando al repo
- ejecuta `./scripts/self_check.sh`
- imprime un resumen corto con repo, dashboard, tab de trabajo y estado general del self-check

## Que automatiza

El launcher evita tener que levantar cada componente a mano todos los dias. Se apoya en comandos ya disponibles y estables:

- `systemctl --user start openclaw-gateway.service`
- `openclaw dashboard --no-open`
- `google-chrome`
- `code`
- `./scripts/self_check.sh`

No toca `~/.openclaw`, no cambia configuracion del gateway y no agrega integraciones nuevas.

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
