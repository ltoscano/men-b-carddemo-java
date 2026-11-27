#!/usr/bin/env bash
# Controllo del segno dei numeri DISPLAY (-fsign=EBCDIC in oracle/cobc.opts).
# Attesi scritti a mano (oracle/segno/expected/) dai byte del file originale, posizioni 133-143 di
# app/data/ASCII/dailytran.txt (DALYTRAN-AMT, PIC S9(09)V99 di CVTRA06Y): undici cifre, l'ultima con il
# segno incorporato secondo la convenzione EBCDIC ('{'=+0, 'A'..'I'=+1..+9, '}'=-0, 'J'..'R'=-1..-9):
#   record  1  0000005047G  -> +000000504,77   ramo CREDITO (CBTRN02C: IF DALYTRAN-AMT >= 0)
#   record  2  0000009190}  -> -000000919,00   ramo DEBITO
#   record 23  0000000709R  -> -000000070,99   ramo DEBITO
#   record 26  0000003250{  -> +000000325,00   ramo CREDITO
# Scrittura: gli stessi importi ricalcolati devono tornare identici byte per byte; le costanti +1, -1, 0 e
# -12,34 devono dare 0000000010{, 0000000010}, 0000000000{, 0000000123M (stessa convenzione).
# La riga CONSOLE (DISPLAY diretto di un campo con segno) e' il formato osservato di GnuCOBOL: cifre e
# segno in coda; non deriva dal sorgente (vedi README).
# 1. Riesegue la prova in una cartella nuova. 2. Confronta. 3. Prove negative, tra cui la sonda compilata
#    davvero SENZA -fsign=EBCDIC (file delle opzioni senza quella riga).
. "$ORACLE_ROOT/lib.sh"

EXP="$ORACLE_ROOT/segno/expected"
tmp="$(mktmp)"
trap 'rm -rf "$tmp"' EXIT

verifica() {
  local obs="$1" errs=0 f
  for f in SEGNOPRB.txt SEGNOOUT.txt SEGNOPRB.ambiente; do
    if [ ! -f "$obs/$f" ]; then echo "$f: assente"; errs=$((errs + 1))
    elif ! diff -u "$EXP/$f" "$obs/$f" > "$tmp/d"; then
      echo "$f: diverso dall'atteso:"; indent "$tmp/d"; errs=$((errs + 1)); fi
  done
  [ "$errs" -eq 0 ] || { echo "verifica fallita: $errs differenze"; return 1; }
  echo "verifica riuscita: 4 importi letti con valore, segno e ramo attesi; byte scritti identici agli originali"
}

log "1. prova del segno rieseguita in una cartella nuova"
SEGNO_OUT_DIR="$tmp/obs" bash "$ORACLE_ROOT/segno/run.sh" || fail "prova del segno fallita"

log "2. confronto con gli attesi"
verifica "$tmp/obs" > "$tmp/v.out" 2>&1 || { cat "$tmp/v.out" >&2; fail "il segno non e' trattato come atteso"; }
indent "$tmp/v.out" >&2

log "3. prove negative"
# Sonda compilata senza -fsign=EBCDIC: stesso file delle opzioni, senza quella riga.
mkdir -p "$tmp/senza/build"
cp "$ORACLE_ROOT/cobc.opts" "$tmp/senza/cobc.opts"
mutate "$tmp/senza/cobc.opts" '/^-fsign=EBCDIC$/d'
orun -v "$tmp/senza/build:/out" -e "UNO_OPZIONI=$(in_container "$tmp/senza/cobc.opts")" -- \
  timeout -k 10 "$ORACLE_TIMEOUT_COMPILE" sh /oracle/build/compile.sh uno eseguibile /oracle/tests/SEGNOPRB.cbl SEGNOPRB /out \
  > "$tmp/senza.log" 2>&1 || { cat "$tmp/senza.log" >&2; fail "compilazione della sonda senza -fsign fallita"; }
grep -qx 'arg -fsign=EBCDIC' "$tmp/senza/build/log/SEGNOPRB.log" && fail "la sonda 'senza' e' stata compilata con -fsign=EBCDIC"
SEGNO_BIN_DIR="$tmp/senza/build/bin" SEGNO_OUT_DIR="$tmp/senza/obs" bash "$ORACLE_ROOT/segno/run.sh" >> "$tmp/senza.log" 2>&1 \
  || { cat "$tmp/senza.log" >&2; fail "esecuzione della sonda senza -fsign fallita"; }
expect_fail "sonda compilata senza -fsign=EBCDIC: -919,00 letto come +919,00" "VALORE= 000000919.00 RAMO=CREDITO" verifica "$tmp/senza/obs"
expect_fail "sonda compilata senza -fsign=EBCDIC: byte scritti diversi" "SEGNOOUT.txt: diverso" verifica "$tmp/senza/obs"
mkdir -p "$tmp/manca"; cp "$tmp/obs/SEGNOPRB.txt" "$tmp/manca/"
expect_fail "contenuto di SEGNOOUT non registrato" "SEGNOOUT.txt: assente" verifica "$tmp/manca"
mkdir -p "$tmp/alt"; cp "$tmp/obs/SEGNOPRB.txt" "$tmp/obs/SEGNOOUT.txt" "$tmp/obs/SEGNOPRB.ambiente" "$tmp/alt/"
mutate "$tmp/alt/SEGNOPRB.txt" 's/VALORE=-000000070.99 RAMO=DEBITO/VALORE=-000000070.99 RAMO=CREDITO/'
expect_fail "ramo del record 23 alterato" "SEGNOPRB.txt: diverso" verifica "$tmp/alt"
mkdir -p "$tmp/amb"; cp "$tmp/obs/SEGNOPRB.txt" "$tmp/obs/SEGNOOUT.txt" "$tmp/obs/SEGNOPRB.ambiente" "$tmp/amb/"
mutate "$tmp/amb/SEGNOPRB.ambiente" '/^LC_ALL=C$/d'
expect_fail "LC_ALL assente dall'ambiente di SEGNOPRB" "SEGNOPRB.ambiente: diverso" verifica "$tmp/amb"
log "controllo superato"
