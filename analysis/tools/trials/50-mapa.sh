#!/usr/bin/env bash
# Prova di mapa (parser JCL): POSTTRAN.jcl, INTCALC.jcl, CREASTMT.JCL, ACCTFILE.jcl.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
require_legacy
ensure_legacy_volume

build_image "$IMG_MAPA" "$DOCKER_DIR/mapa"
rm -rf "$OUT/mapa"
mkdir -p "$OUT/mapa"
work="$(mktmp)"
trap 'rm -rf "$work"' EXIT

printf 'mapa (cartella jcl/, Demo01), commit d05705af310730c3e9aa848e824755e652618512, compilato dai sorgenti\n' > "$OUT/mapa/version.txt"
record mapa command.txt "per ogni file J in POSTTRAN.jcl INTCALC.jcl CREASTMT.JCL ACCTFILE.jcl (percorsi app/jcl/J, dal manifesto):
java -cp class:antlr-4.13.2-complete.jar:commons-cli-1.4.jar Demo01 -file /legacy/app/jcl/J -include /legacy/app/proc -outcsv /work/J.csv
(eseguito in $IMG_MAPA con cartella di lavoro scrivibile; l'output grezzo contiene UUID e orari e non e' deterministico,
quindi si versiona solo la forma normalizzata: jcl_steps.tsv e jcl_dd.tsv)"

for j in POSTTRAN.jcl INTCALC.jcl CREASTMT.JCL ACCTFILE.jcl; do
  grep -q "^app/jcl/$j	jcl$" "$MANIFEST" || fail "$j non risulta jcl nel manifesto"
  tool_run "$IMG_MAPA" "$work" -w /out -- -file "/legacy/app/jcl/$j" -include /legacy/app/proc -outcsv "/out/$j.csv" > "$work/$j.stdout" 2>&1 \
    || { cat "$work/$j.stdout" >&2; fail "mapa fallito su $j"; }
done

glue_run --rw "$work" -- /analysis/tools/glue/normalize.py mapa /work
cp "$work/jcl_steps.tsv" "$work/jcl_dd.tsv" "$OUT/mapa/"
log "mapa: passi e DD scritti in out/mapa/"
