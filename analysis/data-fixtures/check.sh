#!/usr/bin/env bash
# Controlli delle fixture dai dati di esempio (issue #5).
#  0. run.sh, check.sh e deps esistono e sono eseguibili; inventario, fisica, viste, attesi, out/ e documento esistono
#  1. verifica completa con confronto con le uscite versionate (glue/verifica.py --confronta): inventario [I], struttura
#     fisica [F], viste dell'export [V], attesi a mano [D], ricodifica [R], chiavi [K], elenchi ricalcolati in modo
#     indipendente [A][P], uscite versionate [X]; poi out/ e documento rigenerati devono coincidere con i versionati
#  2. conteggi per file: record dalla dimensione (EBCDIC), righe fisiche (ASCII), record decodificati, record attesi
#  3. prove negative su copie private (glue/negativi.py): ognuna con nome e diagnosi; inventario: ogni asserzione
#     (codice di fixture.CODICI) ha almeno una prova superata che la pretende
#  4. prove negative sulla generazione: documento alterato rilevato; confronto con file assente = errore operativo;
#     verifica fallita con un residuo buono di una corsa precedente: errore, e il residuo e' rimosso
# Esiti di diff: 0 uguali, 1 diversi, ogni altro valore errore operativo.
. "$ANALYSIS_ROOT/lib/common.sh"
. "$ANALYSIS_ROOT/tools/lib.sh"
. "$ANALYSIS_ROOT/data-fixtures/lib.sh"
require_legacy

tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

log "0. file dell'analisi"
for f in run.sh check.sh deps; do
  [ -f "$DFX_DIR/$f" ] && [ -x "$DFX_DIR/$f" ] || fail "analysis/data-fixtures/$f assente o non eseguibile"
done
for f in inventario.tsv fisica.tsv viste-export.tsv; do [ -f "$DFX_DIR/$f" ] || fail "analysis/data-fixtures/$f assente"; done
[ -d "$DFX_DIR/attesi" ] && [ -d "$DFX_DIR/out" ] || fail "attesi/ o out/ assenti"
[ -f "$DFX_DOC" ] || fail "docs/legacy-map/fixture.md assente: eseguire './analysis/run.sh data-fixtures'"
log "   ok: run.sh, check.sh, deps eseguibili; inventario, fisica, viste, attesi, out/ e documento presenti"

log "1. verifica completa e confronto con le uscite versionate"
dfx_genera "$tmp/gen" --confronta
confronta() { local rc=0; diff -r "$1" "$2" > "$3" 2>&1 || rc=$?; return "$rc"; }
for coppia in "$tmp/gen/out:$DFX_DIR/out" "$tmp/gen/fixture.md:$DFX_DOC"; do
  rc=0; confronta "${coppia%%:*}" "${coppia#*:}" "$tmp/diff.txt" || rc=$?
  case "$rc" in
    0) ;;
    1) head -30 "$tmp/diff.txt" >&2; fail "${coppia#*:} diverso dal rigenerato: rieseguire './analysis/run.sh data-fixtures'" ;;
    *) cat "$tmp/diff.txt" >&2; fail "confronto non eseguito (diff uscito con $rc)" ;;
  esac
done
esito="$(tail -n 1 "$tmp/gen/verifica.txt")" || fail "esito della verifica illeggibile"
log "   ok: $esito; out/ e documento identici ai versionati"

log "2. conteggi per file"
awk -F'\t' 'NR > 1 { printf "   %-52s dalla dimensione %4s  righe fisiche %4s  decodificati %4s  attesi a mano %2s\n", $1, $2, $3, $4, $5 }' \
  "$tmp/gen/out/conteggi.tsv" >&2 || fail "tabella dei conteggi illeggibile"
incoerenti="$(awk -F'\t' 'NR > 1 && (($2 != "-" && $2 != $4) || ($3 != "-" && $3 != $4) || $5 < 1)' "$tmp/gen/out/conteggi.tsv")" \
  || fail "controllo dei conteggi non eseguito"
[ -z "$incoerenti" ] || fail "conteggi incoerenti: $incoerenti"
log "   ok: per ogni file i record decodificati coincidono con quelli dalla dimensione o con le righe fisiche"

log "3. prove negative su copie private"
rc=0; dfx_negativi "$tmp/neg.txt" || rc=$?
if [ "$rc" -ne 0 ]; then
  grep -A8 "^PROVA NEGATIVA FALLITA\|^ERRORE operativo\|^INVENTARIO" "$tmp/neg.txt" >&2 || tail -40 "$tmp/neg.txt" >&2
  fail "prove negative non superate (uscita $rc)"
fi
ultima="$(tail -n 1 "$tmp/neg.txt")" || fail "esito delle prove negative illeggibile"
case "$ultima" in "prove negative: "*" superate, ogni codice coperto") ;; *) cat "$tmp/neg.txt" >&2; fail "prove negative senza esito riconoscibile" ;; esac
if grep -q "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt"; then fail "una prova negativa e' fallita ma l'uscita e' 0"; fi
sed 's/^/   /' "$tmp/neg.txt" >&2 || fail "uscita delle prove negative illeggibile"

log "4. prove negative sulla generazione"
cp "$DFX_DOC" "$tmp/alterato.md" || fail "copia del documento fallita"
printf '\n- riga aggiunta da una prova negativa\n' >> "$tmp/alterato.md" || fail "alterazione del documento fallita"
rc=0; confronta "$tmp/gen/fixture.md" "$tmp/alterato.md" "$tmp/diff-alterato.txt" || rc=$?
case "$rc" in
  1) ;;
  0) fail "PROVA NEGATIVA FALLITA (documento-alterato): nessuna differenza" ;;
  *) cat "$tmp/diff-alterato.txt" >&2; fail "prova documento-alterato: diff uscito con $rc (errore operativo)" ;;
esac
log "   ok: documento-alterato -> il confronto trova la differenza (diff uscito con 1)"
rc=0; confronta "$tmp/gen/fixture.md" "$tmp/inesistente.md" "$tmp/diff-inesistente.txt" || rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] || fail "PROVA NEGATIVA FALLITA (confronto-file-assente): diff uscito con $rc"
log "   ok: confronto-file-assente -> diff uscito con $rc, errore operativo e non differenza"
# residuo: uscite buone di una corsa precedente e una verifica che fallisce (out/ versionata alterata in una copia)
mkdir -p "$tmp/rotta" && cp -R "$DFX_DIR/." "$tmp/rotta/" || fail "copia dell'analisi non preparata"
mkdir -p "$tmp/res" && cp -R "$tmp/gen/out" "$tmp/gen/fixture.md" "$tmp/gen/verifica.txt" "$tmp/res/" || fail "residuo non preparato"
printf 'riga aggiunta\n' >> "$tmp/rotta/out/totali.tsv" || fail "alterazione dei totali fallita"
rel="${tmp#"$ANALYSIS_ROOT"/}/rotta"
rc=0; ( ensure_legacy_volume
        glue_run --rw "$tmp/res" --mount "$LEGACY_VOL:$DFX_LEGACY:ro" --mount "$DFX_DC:/dc:ro" -- \
          /analysis/data-fixtures/glue/verifica.py "$DFX_LEGACY" /dc /analysis/manifest/sources.tsv /analysis/data-fixtures \
          /work/nuova --confronta "/analysis/$rel/out" ) > "$tmp/res.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { cat "$tmp/res.log" >&2; fail "PROVA NEGATIVA FALLITA (residuo): verifica uscita con $rc invece di 1"; }
grep -q "^ERRORE \[X02\] out/totali.tsv" "$tmp/res.log" || { cat "$tmp/res.log" >&2; fail "prova residuo: fallita ma non per i totali alterati"; }
[ ! -e "$tmp/res/nuova/out" ] || fail "PROVA NEGATIVA FALLITA (residuo): uscite scritte nonostante la verifica fallita"
log "   ok: residuo -> verifica fallita sui totali alterati (X02), nessuna nuova uscita scritta"
log "data-fixtures: tutti i controlli superati"
