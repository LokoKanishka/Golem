# V1.5 Navigation: Golem

## Objetivo
Dar a Golem una capacidad mínima de navegación ampliada sin depender de workers externos.

## Alcance inicial
La primera versión de navegación ampliada incluye:

1. listar pestañas del perfil chrome
2. abrir una URL en el perfil chrome
3. obtener snapshot de la pestaña controlada

## Regla
Esta capacidad depende de que:
- el gateway esté vivo
- el browser relay esté running
- exista al menos una pestaña adjunta cuando haga falta lectura
- o exista un perfil browser gestionado realmente utilizable

## Exclusiones iniciales
Todavía no incluye:
- cambiar activamente de pestaña por índice con lógica compleja
- comparar dos páginas
- buscar texto dentro del DOM
- extracción estructurada avanzada

## Resultado esperado
Golem puede:
- ver qué pestañas tiene disponibles
- abrir una URL operativamente
- leer el estado/snapshot de la pestaña controlada

La verificación honesta del success-path hoy debe pasar por `./scripts/verify_browser_stack.sh`.
