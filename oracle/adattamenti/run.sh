#!/usr/bin/env bash
# Scenario di CBSTM03A (issue #25): il programma che produce gli estratti conto, compilato dalla copia
# adattata (oracle/adattamenti/registro.md), eseguito su quattro file indicizzati piccoli e deterministici.
# 1. Caricamento: IDXLOAD (oracle/tests/) costruisce TRNXFILE, XREFFILE, CUSTFILE e ACCTFILE, in una
#    cartella nuova, dai file di testo versionati in oracle/adattamenti/scenario/.
# 2. Verifica del caricamento, prima di eseguire CBSTM03A: IDXDUMP rilegge ogni file in ordine di chiave e
#    verifica-carico.sh lo confronta record per record con il file di testo. Se il caricamento non e'
#    fedele, lo scenario si ferma qui.
# 3. Esecuzione di CBSTM03A con oracle/esegui.sh: rapporto (codice di uscita, stdout, stderr, file creati),
#    ambiente ricevuto, STMTFILE e HTMLFILE.
# Output in oracle/adattamenti/out/ (ignorato da git): CBSTM03A.txt, CBSTM03A.ambiente, STMTFILE, HTMLFILE,
# carico/, rilettura/, dati/.
# Solo per le prove negative del controllo (tutte le cartelle devono stare sotto oracle/):
#   ADATTAMENTI_OUT_DIR   sposta l'output;
#   ADATTAMENTI_BIN_DIR   usa altri artefatti al posto di quelli della build (niente controllo dell'impronta);
#   ADATTAMENTI_SCENARIO  usa altri file di testo d'ingresso;
#   ADATTAMENTI_SENZA     nome DD (TRNXFILE, XREFFILE, CUSTFILE, ACCTFILE) che CBSTM03A trova assente.
. "$ORACLE_ROOT/lib.sh"

DIR="$ORACLE_ROOT/adattamenti"
scen="${ADATTAMENTI_SCENARIO:-$DIR/scenario}"
out="${ADATTAMENTI_OUT_DIR:-$DIR/out}"
bin="${ADATTAMENTI_BIN_DIR:-$BUILD_OUT/bin}"
senza="${ADATTAMENTI_SENZA:-}"
case "$senza" in ''|TRNXFILE|XREFFILE|CUSTFILE|ACCTFILE) ;; *) fail "ADATTAMENTI_SENZA non valida: '$senza'" ;; esac
require_legacy
ensure_image
[ -n "${ADATTAMENTI_BIN_DIR:-}" ] || require_build
for p in CBSTM03A IDXLOAD IDXDUMP; do [ -x "$bin/$p" ] || fail "$p assente in $(rel "$bin")"; done
[ -d "$scen" ] || fail "scenario assente: $(rel "$scen")"
clean_dir "$out"
scen_c="$(in_container "$scen")"

# 1. Caricamento e rilettura (un solo container; ogni programma ha il limite di tempo di esegui.sh).
orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  timeout -k 10 600 sh /oracle/adattamenti/scenario.sh carica "$scen_c" /out \
  || fail "caricamento dei file indicizzati non completato"
# Ogni caricamento e ogni rilettura devono terminare con 0 e contare tante righe quante ne ha il testo.
for v in TRNXFILE:trnxfile.txt XREFFILE:xreffile.txt CUSTFILE:custfile.txt ACCTFILE:acctfile.txt; do
  dd="${v%%:*}"; f="${v#*:}"
  n="$(wc -l < "$scen/$f" | tr -d ' ')" || fail "lettura di $(rel "$scen/$f") fallita"
  n6="$(printf '%06d' "$n")"
  for r in "carico/$dd/IDXLOAD.txt:IDXLOAD $dd RECORD SCRITTI $n6" "rilettura/$dd/IDXDUMP.txt:IDXDUMP $dd RECORD LETTI $n6"; do
    rf="$out/${r%%:*}"; want="${r#*:}"
    [ -f "$rf" ] || fail "rapporto assente: $(rel "$rf")"
    # Le prime 5 righe del rapporto: codice 0 e stdout fatto della sola riga attesa (la quinta e'
    # l'inizio di stderr: nessuna riga di stdout in piu').
    printf '== codice di uscita\n0\n== stdout\n%s\n== stderr\n' "$want" > "$out/atteso-rapporto.txt"
    testa="$(sed -n '1,5p' "$rf")" || fail "lettura di $(rel "$rf") fallita"
    if [ "$testa" != "$(cat "$out/atteso-rapporto.txt")" ]; then
      indent "$rf" >&2
      fail "caricamento di $dd: $(basename "$rf" .txt) non ha terminato con 0 e '$want'"
    fi
  done
done
rm -f "$out/atteso-rapporto.txt"

# 2. Verifica del caricamento (prima di eseguire CBSTM03A).
orun -v "$out:/out:ro" -- timeout -k 10 120 sh /oracle/adattamenti/verifica-carico.sh "$scen_c" /out \
  > "$out/carico/verifica.txt" 2>&1 || { indent "$out/carico/verifica.txt" >&2; fail "verifica del caricamento fallita"; }
indent "$out/carico/verifica.txt" >&2

# 3. Esecuzione di CBSTM03A.
orun -v "$out:/out" -v "$bin:/oracle-bin:ro" -e ORACLE_TIMEOUT_RUN="$ORACLE_TIMEOUT_RUN" -- \
  timeout -k 10 300 sh /oracle/adattamenti/scenario.sh esegui /out $senza \
  || fail "esecuzione di CBSTM03A non completata"
[ -f "$out/CBSTM03A.txt" ] || fail "rapporto di CBSTM03A assente"
log "CBSTM03A: codice di uscita $(sed -n '2p' "$out/CBSTM03A.txt"); STMTFILE $(wc -c < "$out/STMTFILE" 2>/dev/null | tr -d ' ' || echo assente) byte, HTMLFILE $(wc -c < "$out/HTMLFILE" 2>/dev/null | tr -d ' ' || echo assente) byte"
