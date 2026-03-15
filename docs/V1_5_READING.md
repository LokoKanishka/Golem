# V1.5 Reading: Golem

## Objetivo
Dar a Golem una capacidad mínima de lectura más precisa sobre la pestaña controlada.

## Alcance inicial
La primera versión incluye:

1. obtener snapshot de la pestaña actual
2. buscar una palabra o expresión
3. extraer contexto cercano a la coincidencia

## Regla
Esta capacidad depende de:
- gateway vivo
- browser relay operativo
- al menos una pestaña adjunta
- contenido accesible por snapshot
- o un perfil browser gestionado realmente utilizable

## Exclusiones iniciales
Todavía no incluye:
- parsing semántico avanzado
- extracción estructurada por secciones
- comparación entre dos páginas
- navegación DOM compleja

## Resultado esperado
Golem puede:
- buscar una expresión puntual en la página activa
- devolver coincidencias con contexto
- usar esa lectura como base para respuestas más precisas

La verificación honesta del success-path hoy debe pasar por `./scripts/verify_browser_stack.sh`.
