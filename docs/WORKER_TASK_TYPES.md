# Worker Task Types

Este documento clasifica los tipos de tarea actuales y los posibles tipos futuros respecto de `worker_future`.

## Tipos actuales

| task_type | worker_future a futuro | razon |
| --- | --- | --- |
| self-check | no | chequeo operativo corto y ya resuelto por Golem |
| artifact-find | no | accion acotada y reversible ya formalizada |
| artifact-snapshot | no | snapshot simple, operativo y corto |
| compare-files | no | comparacion local, deterministica y rapida |
| nav-tabs | no | inspeccion minima del estado del browser |
| nav-open | no | requiere validacion humana del destino |
| nav-snapshot | no | lectura acotada del estado actual |
| read-find | no | lectura puntual sobre contexto presente |
| read-snapshot | no | extraccion simple y de corto alcance |

## Candidate worker task types

Estos tipos no existen todavia como capacidades vivas, pero son buenos candidatos para futura delegacion:

| task_type | worker_future | razon |
| --- | --- | --- |
| long-read-report | si | lectura larga con synthesis estructurada y varias secciones |
| bibliography-build | si | armado iterativo de fuentes y referencias |
| repo-analysis | si | analisis largo de multiples carpetas y salidas consolidadas |
| batch-artifact-build | si | generacion repetitiva de varios artefactos en lote |
| multi-step-research | si | investigacion en varias etapas con checkpoints y resumen final |

## Tipos que siguen en humano

Hay categorias que no deberian pasar a worker futuro por defecto:

- cambios estructurales del repo sin alcance claro
- mutaciones de infraestructura o host
- acciones con riesgo alto o confianza externa incierta
- decisiones de prioridad o criterio de negocio

## Regla practica

`worker_future` queda reservado para trabajo:

- largo
- estructurado
- trazable
- con entradas y salida esperada razonablemente definidas

Si una tarea es corta, reversible y ya esta bien soportada por Golem, no hace falta handoff.
