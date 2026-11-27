#!/usr/bin/env bash
# Sentinelle dei tracciati (issue #43): verifica le sentinelle scritte a mano (analysis/data-sentinelle/sentinelle/)
# contro il sorgente e contro i contratti di #3 decodificati con la colla di #23, e rigenera il documento
# docs/legacy-map/data-contract/sentinelle.md. Sentinelle, viste.tsv e colla si scrivono a mano.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-sentinelle/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
dsen_genera "$tmp/out"
cp "$tmp/out/sentinelle.md" "$DSEN_DOC" || fail "impossibile scrivere $DSEN_DOC"
sed 's/^/   /' "$tmp/out/verifica.txt" >&2 || fail "uscita della verifica illeggibile"
esito="$(tail -n 1 "$tmp/out/verifica.txt")" || fail "esito della verifica illeggibile"
log "$esito; documento: docs/legacy-map/data-contract/sentinelle.md"
