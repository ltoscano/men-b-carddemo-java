#!/usr/bin/env bash
# Regole di codifica dei campi (issue #23): rigenera in analysis/data-codec/out/ il censimento delle
# rappresentazioni (dai contratti di #3), l'analisi della pagina di codici dei file EBCDIC e le osservazioni
# della sonda CODECPRB eseguita nell'ambiente dell'oracle. Vettori, colla e documento si scrivono a mano.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-codec/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
dcod_genera "$tmp/out"
rm -rf "$DCOD_DIR/out" || fail "impossibile cancellare analysis/data-codec/out"
[ ! -e "$DCOD_DIR/out" ] || fail "analysis/data-codec/out esiste ancora dopo la cancellazione"
mv "$tmp/out" "$DCOD_DIR/out" || fail "impossibile scrivere analysis/data-codec/out"
log "censimento: $(($(wc -l < "$DCOD_DIR/out/censimento.tsv") - 1)) varianti; osservazioni della sonda: $(($(wc -l < "$DCOD_DIR/out/sonde/osservazioni.tsv") - 1))"
