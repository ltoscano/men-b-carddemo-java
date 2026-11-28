#!/usr/bin/env bash
# Fixture dai dati di esempio (issue #5): decodifica i file di app/data/ASCII e app/data/EBCDIC campo per campo con il
# codec di #23 guidato dai contratti di #3, li verifica contro gli attesi scritti a mano (inventario.tsv, fisica.tsv,
# viste-export.tsv, attesi/) e rigenera analysis/data-fixtures/out/ e docs/legacy-map/fixture.md.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-fixtures/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT
dfx_genera "$tmp/gen"
rm -rf "$DFX_DIR/out" || fail "out/ precedente non rimossa"
cp -R "$tmp/gen/out" "$DFX_DIR/out" || fail "impossibile scrivere analysis/data-fixtures/out/"
cp "$tmp/gen/fixture.md" "$DFX_DOC" || fail "impossibile scrivere $DFX_DOC"
sed 's/^/   /' "$tmp/gen/verifica.txt" >&2 || fail "uscita della verifica illeggibile"
esito="$(tail -n 1 "$tmp/gen/verifica.txt")" || fail "esito della verifica illeggibile"
log "$esito; fixture in analysis/data-fixtures/out/, documento docs/legacy-map/fixture.md"
