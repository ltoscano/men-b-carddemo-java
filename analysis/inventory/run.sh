#!/usr/bin/env bash
# Inventario strutturale e grafo delle dipendenze statiche (issue #2). Rigenera dal legacy:
#   analysis/inventory/out/*.tsv          output normalizzati degli strumenti e della colla (versionati)
#   docs/legacy-map/graph.json            il grafo
#   docs/legacy-map/inventario.md         il riepilogo e le anomalie
# graph.schema.json (a mano) fissa il formato e non viene toccato.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/inventory/lib.sh"
require_legacy
[ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"

work="$(mktmp)"
trap 'rm -rf "$work"' EXIT
inv_generate "$work"

rm -rf "$INV_DIR/out"
mkdir -p "$INV_DIR/out" "$DOCS_DIR"
cp "$work"/out/* "$INV_DIR/out/"
cp "$work/docs/graph.json" "$work/docs/inventario.md" "$DOCS_DIR/"
log "scritti analysis/inventory/out/ ($(ls "$INV_DIR/out" | wc -l | tr -d ' ') file), graph.json e inventario.md"
