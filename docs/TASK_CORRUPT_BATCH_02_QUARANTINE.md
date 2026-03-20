# Corrupt Task Batch 02: Empty File Quarantine

## Propósito

Este tramo trata la primera tanda real de corruptos detectados en el baseline.

El probe previo dejó una conclusión clara:

- los 4 archivos corruptos existen;
- todos tienen `0` bytes;
- todos fallan parseo con `JSONDecodeError` por archivo vacío;
- no contienen estructura recuperable.

Por lo tanto, el tratamiento correcto no es “reparar JSON”.
El tratamiento correcto es:

- aislarlos del carril activo;
- preservarlos como evidencia de incidente;
- dejar manifiesto de cuarentena;
- evitar que sigan contaminando el inventario activo.

---

## Regla de este tramo

Este paso NO inventa contenido para reconstruir tareas vacías.

Solo hace:

1. verifica que el archivo exista;
2. verifica que siga siendo `0` bytes;
3. lo mueve a cuarentena;
4. registra origen y destino;
5. deja un manifiesto auditable.

---

## Ubicación de cuarentena

Los archivos vacíos se aíslan en:

- `tasks/quarantine/corrupt_empty/`

Esto permite:

- sacar el ruido del carril activo;
- no mezclarlos con `archive/`;
- no fingir que son tareas cerradas válidas;
- conservarlos para auditoría posterior.

---

## Manifiesto

El tratamiento debe dejar:

- path original;
- tamaño original;
- path de cuarentena;
- motivo del aislamiento.

---

## Implicación

Con esta cuarentena cerrada, el inventario activo deja de estar contaminado por estos 4 vacíos.

Después de eso, el paso correcto es:

1. rerun del baseline;
2. confirmar que `corrupt=0`;
3. pasar a la primera tanda chica de `legacy` migrable real.

