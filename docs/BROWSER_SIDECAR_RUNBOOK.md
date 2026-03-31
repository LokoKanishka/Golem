# Browser Sidecar Runbook

## Que es

El browser sidecar es el carril browser operativo oficial de Golem.

No usa `openclaw browser ...` como superficie diaria.
Usa un Chrome dedicado con CDP y los wrappers `browser_sidecar_*`.

## Por que se acepta

Se acepta porque hoy es el unico carril browser que ya quedo en `PASS` para:

- listar tabs reales
- leer una pagina real
- buscar texto real
- navegar y leer paginas publicas reales simples

La deuda congelada queda en el browser nativo de OpenClaw.

## Configuracion por defecto

- puerto CDP: `9222`
- URL CDP: `http://127.0.0.1:9222`
- root runtime: `/tmp/golem-browser-sidecar`
- profile runtime: `/tmp/golem-browser-sidecar/profile`
- log runtime: `/tmp/golem-browser-sidecar/chrome.log`

Overrides soportados:

- `GOLEM_BROWSER_SIDECAR_ROOT`
- `GOLEM_BROWSER_SIDECAR_PORT`
- `GOLEM_BROWSER_SIDECAR_URL`
- `GOLEM_BROWSER_SIDECAR_PROFILE_DIR`
- `GOLEM_BROWSER_SIDECAR_PIDFILE`
- `GOLEM_BROWSER_SIDECAR_LOGFILE`
- `GOLEM_BROWSER_SIDECAR_BROWSER_BIN`

## Lifecycle

Arrancar:

```bash
./scripts/browser_sidecar_start.sh
```

Ver estado:

```bash
./scripts/browser_sidecar_status.sh
```

Apagar:

```bash
./scripts/browser_sidecar_stop.sh
```

## Comandos diarios

Abrir URL:

```bash
./scripts/browser_sidecar_open.sh http://127.0.0.1:8011/
```

Listar tabs:

```bash
./scripts/browser_sidecar_tabs.sh
```

Seleccionar una tab por indice, titulo parcial o URL parcial:

```bash
./scripts/browser_sidecar_select.sh 0
./scripts/browser_sidecar_select.sh "Reserved Domains"
./scripts/browser_sidecar_select.sh rfc-editor.org
```

Si el selector es ambiguo, el script falla y muestra los matches.

Leer una tab de forma directa:

```bash
./scripts/browser_sidecar_read.sh
./scripts/browser_sidecar_read.sh "Reserved Domains"
./scripts/browser_sidecar_read.sh rfc-editor.org
./scripts/browser_sidecar_read.sh https://www.iana.org/domains/reserved
```

Snapshot de la tab actual o por selector:

```bash
./scripts/browser_sidecar_snapshot.sh
./scripts/browser_sidecar_snapshot.sh "Golem Browser Truth"
./scripts/browser_sidecar_snapshot.sh http://127.0.0.1:8011/
```

Buscar texto:

```bash
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415 "Golem Browser Truth"
./scripts/browser_sidecar_find.sh CAPYBARA_SIGNAL_31415 http://127.0.0.1:8011/
```

## Verify

Verify truth mas profunda:

```bash
./scripts/verify_browser_capability_truth.sh
```

Verify operativa corta:

```bash
./scripts/verify_browser_sidecar_operational.sh
```

Verify real sobre web publica simple:

```bash
./scripts/verify_browser_sidecar_real_web.sh
```

Targets hoy probados de forma explicita:

- `https://www.iana.org/domains/reserved`
- `https://www.rfc-editor.org/rfc/rfc2606.html`

## Que NO promete

- no arregla `openclaw browser ...`
- no usa el Chrome ambient como contrato confiable
- no promete login, clicks complejos o formularios
- no promete scraping general de sitios frágiles o anti-bot
- no promete control host total
- no reabre MCP, plugins ni workers
- no convierte al browser nativo de OC en sano

## Deuda congelada

La deuda congelada es explicita:

- `browser nativo OC = BLOCKED`
- el carril operativo de browser real va por sidecar
