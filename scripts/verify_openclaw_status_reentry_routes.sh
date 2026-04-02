#!/usr/bin/env bash
set -euo pipefail

DOC="docs/CURRENT_STATE.md"

fail() {
  echo "VERIFY_FAIL: $1" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "missing $DOC"

patterns=(
  "## Status Reentry Routes"
  '`status pre-closure chain`'
  "docs/OPENCLAW_STATUS_PRE_CLOSURE_INDEX.md"
  "navegar rapido la cadena previa de evidencia -> consistency -> artifact -> workflow -> drafting -> finalization -> closure-notes"
  "entrar por esta ruta cuando todavia haga falta entender o producir la cadena read-side previa al cierre real"
  '`status real closures already materialized`'
  "docs/OPENCLAW_STATUS_REAL_CLOSURE_INDEX.md"
  'elegir rapido entre reentrada corta (`quick-reentry`) y verdad operativa corta (`state-check`)'
  "entrar por esta ruta cuando la cadena previa ya no es la duda y haga falta leer cierres reales ya materializados"
  "no delivery real, no browser usable, no readiness total, no runtime changes, no reactivar WhatsApp"
  'ninguna de estas rutas reemplaza `docs/CURRENT_STATE.md` ni `handoffs/HANDOFF_CURRENT.md`'
)

for pattern in "${patterns[@]}"; do
  grep -Fq "$pattern" "$DOC" || fail "missing pattern '$pattern' in $DOC"
done

echo "VERIFY_OK: openclaw status reentry routes checks passed"
