# Golem Acceptance Test

Este directorio guarda las corridas persistidas del acceptance test general del stack.

Como correrlo:

- `./scripts/golem_acceptance_test.sh`

Que cubre:

- integridad basica del repo local y remoto configurado
- gate oficial del carril canonico
- task API y panel HTTP
- mejor prueba disponible de superficie visible del panel
- task API y bridge como servicios
- query, mutate y runtime del carril de WhatsApp
- stack diario del host
- diagnostico host-level y una falla controlada

Que no cubre:

- envio real a proveedores externos fuera de los smokes aceptados
- todas las combinaciones posibles de fallas del host
- performance, carga o endurance

Como leer el resultado:

- `summary.txt`: lectura humana con estado por bloque y veredicto global
- `manifest.json`: indice estructurado con bloques, checks, exit codes y rutas de log
- `checks.tsv`: tabla plana de subpruebas
- `logs/`: salida completa de cada check orquestado
