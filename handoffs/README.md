# Handoffs

Esta carpeta guarda handoff packets preparados para Codex u otro worker futuro.

## Que se guarda aca

Cada archivo de `handoffs/` representa una tarea ya delegada convertida en un packet legible y reutilizable.

Formato actual:

```text
handoffs/<task_id>.md
```

## Relacion entre `tasks/` y `handoffs/`

- `tasks/` sigue siendo la fuente de verdad del estado de la tarea
- `handoffs/` guarda una vista preparada para delegacion operativa

En otras palabras:

- la tarea registra el trabajo y su estado
- el handoff packet resume y empaqueta esa tarea para Codex

## Que no significa

Un handoff packet no es:

- trabajo ejecutado
- resultado final
- callback de worker
- evidencia de cierre

Es solamente un artefacto de delegacion.
