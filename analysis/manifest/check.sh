#!/usr/bin/env bash
# Controlli sul manifesto: coincide con `git ls-files`, nessun duplicato/extra, tipi ammessi,
# 44 file cobol di cui 31 sotto app/cbl/, riproducibilita'; e test negativi.
. "$ANALYSIS_ROOT/lib/common.sh"
require_legacy

here="$(pwd)"
exp=/analysis/tools/expected/manifest.tsv
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

[ -f "$here/sources.tsv" ] || fail "sources.tsv assente: eseguire prima './analysis/run.sh manifest'"

log "1. manifesto contro git ls-files e attesi scritti a mano"
legacy_ls_files | glue_run --stdin -- /analysis/manifest/verify.py /analysis/manifest/sources.tsv "$exp"

log "2. riproducibilita': due rigenerazioni identiche tra loro e al file versionato"
legacy_ls_files | glue_run --stdin -- /analysis/manifest/classify.py > "$tmp/a.tsv"
legacy_ls_files | glue_run --stdin -- /analysis/manifest/classify.py > "$tmp/b.tsv"
cmp -s "$tmp/a.tsv" "$tmp/b.tsv" || fail "due rigenerazioni consecutive differiscono"
cmp -s "$tmp/a.tsv" "$here/sources.tsv" || fail "sources.tsv versionato diverso dalla rigenerazione: rieseguire il manifesto"

log "3. test negativo: manifesto con un file omesso e un altro file dello stesso tipo (copybook) duplicato deve far fallire il controllo"
glue_run --rw "$tmp" -- /analysis/manifest/tamper.py manifest /analysis/manifest/sources.tsv /work/tampered.tsv
if legacy_ls_files | glue_run --rw "$tmp" --stdin -- /analysis/manifest/verify.py /work/tampered.tsv "$exp" 2> "$tmp/neg1.err"; then
  fail "il controllo NON ha rilevato il manifesto alterato"
fi
grep -q 'assente dal manifesto: app/cpy/CVACT01Y.cpy' "$tmp/neg1.err" || fail "il file omesso non e' stato segnalato"
grep -q 'percorso duplicato nel manifesto: app/cpy/CVACT03Y.cpy' "$tmp/neg1.err" || fail "il duplicato non e' stato segnalato"
log "   fallisce come previsto: $(wc -l < "$tmp/neg1.err" | tr -d ' ') discrepanze segnalate"

log "4. test negativo: valore atteso alterato (31 -> 30 programmi sotto app/cbl) deve far fallire il controllo"
glue_run --rw "$tmp" -- /analysis/manifest/tamper.py expected "$exp" /work/expected_bad.tsv
if legacy_ls_files | glue_run --rw "$tmp" --stdin -- /analysis/manifest/verify.py /analysis/manifest/sources.tsv /work/expected_bad.tsv 2> "$tmp/neg2.err"; then
  fail "il controllo NON ha rilevato l'atteso alterato"
fi
grep -q 'cobol_sotto_app_cbl: atteso 30, trovato 31' "$tmp/neg2.err" || fail "discrepanza sull'atteso non segnalata"
log "   fallisce come previsto"
log "manifesto: tutti i controlli superati"
