#!/usr/bin/env bash
# Comandi EXEC CICS nella mappa del legacy (issue #22). Rigenera dal legacy:
#   analysis/inventory-cics/out/blocchi.tsv   blocchi estratti con ProLeap, comando e opzioni (versionato)
#   docs/legacy-map/graph-cics.json            occorrenze, archi e nodi nuovi (riferimenti ai nodi di graph.json)
#   docs/legacy-map/inventario-cics.md         riepilogo, regole e limiti
# graph-cics.schema.json (a mano) fissa il formato e non viene toccato; graph.json di #2 e' solo letto.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/inventory-cics/lib.sh"
require_legacy
[ -f "$MANIFEST" ] || fail "manifesto assente: eseguire prima './analysis/run.sh manifest'"
[ -f "$DOCS_DIR/graph.json" ] || fail "docs/legacy-map/graph.json assente: eseguire prima './analysis/run.sh inventory'"

work="$(mktmp)"
trap 'rm -rf "$work"' EXIT
cics_generate "$work"

rm -rf "$CICS_DIR/out"
mkdir -p "$CICS_DIR/out"
cp "$work/out/blocchi.tsv" "$CICS_DIR/out/"
cp "$work/docs/graph-cics.json" "$work/docs/inventario-cics.md" "$DOCS_DIR/"
log "scritti analysis/inventory-cics/out/blocchi.tsv ($(($(wc -l < "$CICS_DIR/out/blocchi.tsv") - 1)) blocchi), graph-cics.json e inventario-cics.md"
