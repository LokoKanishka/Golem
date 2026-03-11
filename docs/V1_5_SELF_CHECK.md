# V1.5 Self-Check: Golem

## Objetivo
Dar a Golem una capacidad mínima de autodiagnóstico operativo.

## Qué chequea
1. Gateway
2. WhatsApp
3. Browser relay
4. Tabs adjuntas
5. Estado general

## Criterios

### Gateway
- OK: systemd activo + runtime running + RPC probe ok
- WARN: systemd activo pero falta alguna señal fuerte
- FAIL: gateway caído o no responde

### WhatsApp
- OK: enabled + linked + running + connected
- WARN: configurado pero no conectado del todo
- FAIL: no reachable o no vinculado

### Browser relay
- OK: perfil chrome running
- WARN: perfil chrome existe pero sin actividad clara
- FAIL: perfil no disponible o error

### Tabs adjuntas
- OK: al menos 1 tab adjunta
- WARN: relay activo pero 0 tabs
- FAIL: error al consultar tabs

## Salida esperada
- líneas por componente
- síntesis final
- estado general: OK / WARN / FAIL

## Regla
En V1.5, self-check observa y reporta.
Todavía no repara automáticamente.
