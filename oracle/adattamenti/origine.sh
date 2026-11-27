#!/bin/sh
# Eseguito DENTRO il container dell'oracle da oracle/adattamenti/check.sh. Verifica la provenienza dei file
# di testo dello scenario dichiarata in scenario/origine.tsv, rifacendo la trasformazione sui dati di
# esempio del legacy (/legacy/app/data/ASCII/):
#   copia   la riga dello scenario e' identica alla riga dei dati di esempio;
#   outrec  la riga dello scenario e' l'OUTREC di app/jcl/CREASTMT.JCL (riga 54: 1:263,16 / 17:1,262 /
#           279:279,50) applicato alla riga dei dati di esempio, piu' 22 spazi fino a 350 byte.
# Ogni riga di ogni file dello scenario deve avere una e una sola provenienza dichiarata.
# Stampa una riga "DIFETTO: ..." per ogni difetto e alla fine l'esito; esce con 1 se c'e' un difetto.
# Uso: origine.sh SCENARIO
set -u
[ $# -eq 1 ] || { echo "uso: origine.sh SCENARIO" >&2; exit 2; }
scen="$1"; dati=/legacy/app/data/ASCII
TAB="$(printf '\t')"
errs=0
err() { echo "DIFETTO: $*"; errs=$((errs + 1)); }
[ -f "$scen/origine.tsv" ] || { echo "DIFETTO: origine.tsv assente"; exit 1; }
w="$(mktemp -d /tmp/origine.XXXXXX)" || { echo "DIFETTO: cartella temporanea non creabile"; exit 1; }
[ -r "$scen/origine.tsv" ] || { echo "DIFETTO: origine.tsv illeggibile"; exit 1; }
grep -v '^#' "$scen/origine.tsv" > "$w/senza-commenti.tsv"; rc=$?
[ "$rc" -le 1 ] || { echo "DIFETTO: lettura di origine.tsv fallita (grep $rc)"; exit 1; }
tail -n +2 "$w/senza-commenti.tsv" > "$w/righe.tsv" || { echo "DIFETTO: lettura di origine.tsv fallita"; exit 1; }
: > "$w/dichiarate"
while IFS="$TAB" read -r f r src rs tr; do
  case "$r$rs" in ''|*[!0-9]*) err "origine.tsv: riga '$f $r $src $rs $tr' con numeri di riga non validi"; continue ;; esac
  case "$f" in trnxfile.txt|xreffile.txt|custfile.txt|acctfile.txt) ;; *) err "origine.tsv: file dello scenario sconosciuto '$f'"; continue ;; esac
  [ -f "$scen/$f" ] || { err "$f: file dello scenario assente"; continue; }
  [ -f "$dati/$src" ] || { err "$src: file dei dati di esempio assente"; continue; }
  sed -n "${r}p" "$scen/$f" > "$w/s" || { err "$f: lettura fallita"; continue; }
  [ -s "$w/s" ] || { err "$f riga $r: assente"; continue; }
  case "$tr" in
    copia)  sed -n "${rs}p" "$dati/$src" > "$w/a" || { err "$src: lettura fallita"; continue; } ;;
    outrec) awk -v n="$rs" 'NR == n {printf "%s%s%s%22s\n", substr($0, 263, 16), substr($0, 1, 262), substr($0, 279, 50), ""}' "$dati/$src" > "$w/a" \
              || { err "$src: lettura fallita"; continue; } ;;
    *) err "$f riga $r: trasformazione sconosciuta '$tr'"; continue ;;
  esac
  [ -s "$w/a" ] || { err "$src riga $rs: assente"; continue; }
  cmp -s "$w/a" "$w/s" || err "$f riga $r: diversa da $src riga $rs ($tr)"
  echo "$f $r" >> "$w/dichiarate"
done < "$w/righe.tsv"
# Ogni riga dei file dello scenario dichiarata una e una sola volta.
for f in trnxfile.txt xreffile.txt custfile.txt acctfile.txt; do
  [ -f "$scen/$f" ] || { err "$f: file dello scenario assente"; continue; }
  n="$(wc -l < "$scen/$f")" || { err "$f: illeggibile"; continue; }
  n="$(echo "$n" | tr -d ' ')"
  [ "$n" -gt 0 ] 2>/dev/null || { err "$f: vuoto o illeggibile"; continue; }
  i=1
  while [ "$i" -le "$n" ]; do
    c="$(grep -cx "$f $i" "$w/dichiarate")"; [ $? -le 1 ] || c="?"
    [ "$c" = 1 ] || err "$f riga $i: provenienza dichiarata $c volte in origine.tsv"
    i=$((i + 1))
  done
done
tot="$(wc -l < "$w/righe.tsv" | tr -d ' ')"
rm -rf "$w"
if [ "$errs" -eq 0 ]; then echo "provenienza verificata: $tot righe dello scenario uguali ai dati di esempio dichiarati (copia o OUTREC di CREASTMT.JCL)"; exit 0; fi
echo "verifica della provenienza fallita: $errs difetti"; exit 1
