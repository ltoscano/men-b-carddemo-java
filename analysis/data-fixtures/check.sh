#!/usr/bin/env bash
# Controlli delle fixture dai dati di esempio (issue #5).
#  0. run.sh, check.sh e deps esistono e sono eseguibili; inventario, fisica, viste, attesi, out/ e documento esistono
#  1. verifica completa con confronto con le uscite versionate (glue/verifica.py --confronta): inventario [I], struttura
#     fisica [F], viste dell'export [V], attesi a mano [D], ricodifica [R], chiavi [K], elenchi ricalcolati in modo
#     indipendente [A][P], andata e ritorno contro i byte del file letti per altra via [R04], coppie dovute [I10],
#     tabelle del documento [X04], uscite versionate [X]; poi out/ e documento rigenerati devono coincidere con i versionati
#  2. conteggi per file: record dalla dimensione (EBCDIC), righe fisiche (ASCII), record decodificati, record attesi
#  3. prove negative su copie private (glue/negativi.py): ognuna con nome e diagnosi; inventario: ogni guardia (ogni
#     chiamata es.errore censita nel sorgente di fixture.py e verificatore.py) e' scattata in almeno una prova superata
#     che pretende il suo codice; alcune prove girano senza il confronto con i versionati (alterazione + rigenerazione)
#  4. prove negative sulla generazione: documento alterato rilevato; confronto con file assente = errore operativo;
#     dfx_genera con un residuo buono nella sua destinazione e una verifica che fallisce: errore, residuo rimosso
#  5. prove negative sugli esiti: tail che fallisce dopo aver stampato il testo giusto; grep che esce con 2
# Esiti: diff e grep 0 / 1 / altro (errore operativo, mai scambiato per differenza o assenza).
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
esito="$(dfx_esito "$tmp/gen/verifica.txt")" || fail "esito della verifica illeggibile"
log "   ok: $esito; out/ e documento identici ai versionati"

log "2. conteggi per file"
awk -F'\t' 'NR > 1 { printf "   %-52s dalla dimensione %4s  righe fisiche %4s  decodificati %4s  attesi a mano %2s\n", $1, $2, $3, $4, $5 }' \
  "$tmp/gen/out/conteggi.tsv" >&2 || fail "tabella dei conteggi illeggibile"
incoerenti="$(awk -F'\t' 'NR > 1 && (($2 != "-" && $2 != $4) || ($3 != "-" && $3 != $4) || $5 < 1)' "$tmp/gen/out/conteggi.tsv")" \
  || fail "controllo dei conteggi non eseguito"
[ -z "$incoerenti" ] || fail "conteggi incoerenti: $incoerenti"
log "   ok: per ogni file i record decodificati coincidono con quelli dalla dimensione o con le righe fisiche"

# presenza MODELLO FILE: 0 se una riga corrisponde, 1 se nessuna, 2 se grep non ha potuto leggere (mai preso per assenza)
presenza() { local rc=0; grep -q -- "$1" "$2" || rc=$?; case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac; }

log "3. prove negative su copie private"
rc=0; dfx_negativi "$tmp/neg.txt" || rc=$?
if [ "$rc" -ne 0 ]; then
  rg=0; grep -A8 "^PROVA NEGATIVA FALLITA\|^ERRORE operativo\|^INVENTARIO" "$tmp/neg.txt" >&2 || rg=$?
  case "$rg" in 0) ;; 1) tail -40 "$tmp/neg.txt" >&2 || true ;; *) log "   uscita delle prove negative illeggibile (grep $rg)" ;; esac
  fail "prove negative non superate (uscita $rc)"
fi
ultima="$(tail -n 1 "$tmp/neg.txt")" || fail "esito delle prove negative illeggibile"
case "$ultima" in "prove negative: "*" superate, ogni sito coperto") ;; *) cat "$tmp/neg.txt" >&2; fail "prove negative senza esito riconoscibile" ;; esac
rc=0; presenza "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt" || rc=$?
case "$rc" in
  1) ;;
  0) fail "una prova negativa e' fallita ma l'uscita e' 0" ;;
  *) fail "uscita delle prove negative illeggibile (grep $rc)" ;;
esac
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
# residuo: uscite buone di una corsa precedente NELLA DESTINAZIONE di dfx_genera, e una verifica che fallisce (un atteso
# a mano alterato in una copia privata dell'analisi): dfx_genera deve fallire e il residuo non deve restare
mkdir -p "$tmp/rotta" && cp -R "$DFX_DIR/." "$tmp/rotta/" || fail "copia dell'analisi non preparata"
f="$tmp/rotta/attesi/AWS.M2.CARDDEMO.DALYTRAN.PS.tsv"
rc=0; presenza "	-919.00	" "$f" || rc=$?
[ "$rc" -eq 0 ] || fail "valore da alterare assente in $f (grep $rc)"
sed 's/	-919\.00	/	-919.01	/' "$f" > "$f.nuovo" && mv "$f.nuovo" "$f" || fail "alterazione dell'atteso fallita"
rc=0; presenza "	-919.01	" "$f" || rc=$?
[ "$rc" -eq 0 ] || fail "alterazione dell'atteso non applicata (grep $rc)"
mkdir -p "$tmp/res" && cp -R "$tmp/gen/out" "$tmp/gen/fixture.md" "$tmp/gen/verifica.txt" "$tmp/res/" || fail "residuo non preparato"
[ -d "$tmp/res/out" ] && [ -s "$tmp/res/fixture.md" ] || fail "residuo non preparato nella destinazione"
rc=0; ( dfx_genera "$tmp/res" --confronta "$tmp/rotta" ) > "$tmp/res.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { cat "$tmp/res.log" >&2; fail "PROVA NEGATIVA FALLITA (residuo): dfx_genera uscita con $rc invece di 1"; }
rc=0; presenza "^ERRORE \[D02\] AWS.M2.CARDDEMO.DALYTRAN.PS#2 DALYTRAN-AMT" "$tmp/res.log" || rc=$?
[ "$rc" -eq 0 ] || { cat "$tmp/res.log" >&2; fail "prova residuo: fallita ma non per l'atteso alterato (grep $rc)"; }
[ ! -e "$tmp/res/out" ] && [ ! -e "$tmp/res/fixture.md" ] || fail "PROVA NEGATIVA FALLITA (residuo): le uscite della corsa precedente sono rimaste"
log "   ok: residuo -> dfx_genera fallita (uscita 1) su [D02] con il residuo nella sua destinazione, residuo rimosso"

log "5. prove negative sugli esiti degli script"
rc=0; ( tail() { command tail "$@"; return 7; }; dfx_esito "$tmp/gen/verifica.txt" ) > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "PROVA NEGATIVA FALLITA (tail-fallito): dfx_esito uscita con $rc invece di 2"
log "   ok: tail-fallito -> tail che stampa il testo giusto ma esce con 7: dfx_esito esce con 2 (errore operativo)"
rc=0; ( grep() { return 2; }; presenza "^PROVA NEGATIVA FALLITA" "$tmp/neg.txt" ) || rc=$?
[ "$rc" -eq 2 ] || fail "PROVA NEGATIVA FALLITA (grep-fallito): presenza uscita con $rc invece di 2"
log "   ok: grep-fallito -> grep uscito con 2: presenza esce con 2, non scambiato per assenza"
log "data-fixtures: tutti i controlli superati"
