#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/run.sh, dopo il caricamento e prima di
# eseguire CBSTM03A. Verifica che i quattro file indicizzati contengano esattamente i file di testo
# d'ingresso: confronta la rilettura di IDXDUMP (OUT/rilettura/<DD>.bin, i record in ordine di chiave,
# senza separatori) con il file di testo, record per record: stesso numero di record, stessi byte, quindi
# stesse chiavi nello stesso ordine; ogni record lungo quanto dichiarato in CBSTM03B, con la riga di testo
# all'inizio e spazi fino alla fine (riempimento dichiarato in scenario/origine.tsv e registro.md).
# Le righe di testo devono avere la lunghezza dichiarata: 350, 36 (XREF: 14 byte di FILLER di CVACT03Y
# riempiti con spazi), 500, 300.
# Stampa una riga "DIFETTO: ..." per ogni difetto e alla fine l'esito; esce con 1 se c'e' un difetto.
# Uso: verifica-carico.sh SCENARIO OUT
set -u
[ $# -eq 2 ] || { echo "uso: verifica-carico.sh SCENARIO OUT" >&2; exit 2; }
scen="$1"; out="$2"
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
w="$(mktemp -d /tmp/verifica-carico.XXXXXX)" || { echo "DIFETTO: cartella temporanea non creabile"; exit 1; }
riass=""
# DD:file di testo:lunghezza del record (CBSTM03B, righe 58-78):lunghezza della riga di testo
for v in TRNXFILE:trnxfile.txt:350:350 XREFFILE:xreffile.txt:50:36 CUSTFILE:custfile.txt:500:500 ACCTFILE:acctfile.txt:300:300; do
  dd="$(echo "$v" | cut -d: -f1)"; f="$(echo "$v" | cut -d: -f2)"
  L="$(echo "$v" | cut -d: -f3)"; T="$(echo "$v" | cut -d: -f4)"
  txt="$scen/$f"; bin="$out/rilettura/$dd.bin"
  [ -f "$txt" ] || { err "$dd: file di testo assente ($f)"; continue; }
  [ -f "$bin" ] || { err "$dd: rilettura assente"; continue; }
  bad="$(awk -v T="$T" 'length($0) != T {printf "%d(%d) ", NR, length($0)}' "$txt")" || { err "$dd: lettura di $f fallita"; continue; }
  [ -z "$bad" ] || err "$dd: righe di $f con lunghezza diversa da $T: $bad"
  n="$(wc -l < "$txt")" || { err "$dd: righe di $f non contabili"; continue; }
  n="$(echo "$n" | tr -d ' ')"
  [ "$n" -gt 0 ] || { err "$dd: $f vuoto"; continue; }
  # Atteso: ogni riga riempita con spazi fino a L byte, record contigui.
  awk -v L="$L" '{printf "%-" L "s", $0}' "$txt" > "$w/$dd.atteso" || { err "$dd: costruzione dell'atteso fallita"; continue; }
  sb="$(wc -c < "$bin")" || { err "$dd: dimensione della rilettura non leggibile"; continue; }
  sb="$(echo "$sb" | tr -d ' ')"
  [ "$sb" -eq $((n * L)) ] || err "$dd: riletti $sb byte, attesi $n record da $L byte ($((n * L)))"
  if ! cmp -s "$w/$dd.atteso" "$bin"; then
    # Primo byte diverso: record e posizione nel record.
    # cmp (GNU diffutils) scrive "... differ: char N, line M" (o "byte N"); con un file piu' corto "EOF".
    p="$(cmp "$w/$dd.atteso" "$bin" 2>&1 | sed -n 's/.* differ: [a-z]* \([0-9][0-9]*\),.*/\1/p' | head -n 1)"
    if [ -n "$p" ]; then
      err "$dd: contenuto riletto diverso dal file di testo: primo byte diverso nel record $(( (p - 1) / L + 1 )), posizione $(( (p - 1) % L + 1 ))"
    else
      err "$dd: contenuto riletto diverso dal file di testo ($(cmp "$w/$dd.atteso" "$bin" 2>&1 | head -n 1))"
    fi
  fi
  chiavi="$(case "$dd" in TRNXFILE) k=32 ;; XREFFILE) k=16 ;; CUSTFILE) k=9 ;; ACCTFILE) k=11 ;; esac
            cut -c1-$k "$txt" | tr '\n' ' ')"
  riass="$riass
  $dd: $n record da $L byte, chiavi in ordine: $chiavi"
done
rm -rf "$w"
if [ "$errs" -eq 0 ]; then echo "caricamento verificato, record per record:$riass"; exit 0; fi
echo "verifica del caricamento fallita: $errs difetti"; exit 1
