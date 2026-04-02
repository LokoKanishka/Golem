# WhatsApp Safety Contract

Fecha de actualizacion: 2026-04-01

## Objetivo

Ningun mensaje interno de pairing, access, debug o aprobacion puede salir a chats reales de WhatsApp.

## Contrato tecnico

- WhatsApp queda `deny-by-default`.
- Ningun mensaje sale si el canal no esta habilitado de forma explicita.
- Ningun mensaje sale si el target no es explicito y no ambiguo.
- Ningun mensaje sale si el sender/target no esta allowlisteado para el bridge runtime.
- Eventos internos de pairing/access en WhatsApp se registran localmente; no se responden por WhatsApp real.
- La ausencia del flag `~/.config/openclaw/whatsapp.enable` bloquea el arranque de:
  - `openclaw-gateway.service`
  - `openclaw-direct-chat.service`
  - `fusion-total-direct-chat.service`
- La config viva debe dejar `channels.whatsapp.enabled=false` y `dmPolicy="disabled"` hasta nueva verificacion.

## Kill Switch

- Inmediato:
  - `systemctl --user stop openclaw-gateway.service openclaw-direct-chat.service fusion-total-direct-chat.service`
  - `systemctl --user mask --runtime openclaw-gateway.service openclaw-direct-chat.service fusion-total-direct-chat.service`
- Persistente:
  - drop-ins `10-whatsapp-kill-switch.conf` en cada unit
  - flag ausente: `~/.config/openclaw/whatsapp.enable`

## Condiciones minimas para reactivar

- patch fail-closed aplicado sobre la instalacion viva
- config viva de WhatsApp revisada y habilitada de forma intencional
- `./scripts/verify_whatsapp_fail_closed.sh` pasa
- decision explicita de volver a crear el flag `~/.config/openclaw/whatsapp.enable`
- `unmask/start` controlado y auditado

## Verify oficial

- `./scripts/verify_whatsapp_fail_closed.sh`

La respuesta esperada a la pregunta "¿OpenClaw puede volver a mandar mensajes de control a chats personales?" debe ser:

`NO`
