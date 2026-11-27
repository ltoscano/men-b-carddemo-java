#!/usr/bin/env bash
# Prova di GnuCOBOL: cobc -fsyntax-only (dialetto IBM) su tutti i programmi di app/cbl/ presi dal manifesto.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_COBC" "$DOCKER_DIR/gnucobol"
rm -rf "$OUT/gnucobol"
mkdir -p "$OUT/gnucobol"

docker run --rm "$IMG_COBC" --version | head -1 > "$OUT/gnucobol/version.txt"
app_cbl_programs > "$OUT/gnucobol/programs.txt"
record gnucobol command.txt "per ogni programma P di app/cbl/ (elenco dal manifesto, in programs.txt):
cobc -fsyntax-only -std=ibm -I /legacy/app/cpy -I /legacy/app/cpy-bms /legacy/<P>
(eseguito in $IMG_COBC; i sorgenti non vengono modificati né pre-elaborati)"

tool_run "$IMG_COBC" "$OUT/gnucobol" \
  -v "$DOCKER_DIR/gnucobol/syntax.sh:/syntax.sh:ro" \
  -v "$OUT/gnucobol/programs.txt:/in/programs.txt:ro" \
  --entrypoint sh -- /syntax.sh
log "gnucobol: $(( $(wc -l < "$OUT/gnucobol/syntax.tsv") - 1 )) programmi compilati in sola sintassi"
